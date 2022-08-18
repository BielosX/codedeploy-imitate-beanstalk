#!/usr/bin/python3

import os
import boto3
import time
from functools import reduce
from botocore.config import Config

boto_config = Config(region_name = 'eu-west-1')

elbv2_client = boto3.client('elbv2', config=boto_config)
codedeploy_client = boto3.client('codedeploy', config=boto_config)

app_name = os.environ['APPLICATION_NAME']
deployment_group_name = os.environ['DEPLOYMENT_GROUP_NAME']

response = codedeploy_client.get_deployment_group(
    applicationName=app_name,
    deploymentGroupName=deployment_group_name
)
target_group_name = response['deploymentGroupInfo']['loadBalancerInfo']['targetGroupInfoList'][0]['name']
target_group_details = elbv2_client.describe_target_groups(
    Names=[target_group_name]
)['TargetGroups'][0]
target_group_arn = target_group_details['TargetGroupArn']
health_check_interval = target_group_details['HealthCheckIntervalSeconds']
health_check_timeout = target_group_details['HealthCheckTimeoutSeconds']
unhealthy_threshold = target_group_details['UnhealthyThresholdCount']
wait_time = float(unhealthy_threshold * (health_check_interval + health_check_timeout)) * 2.0
time.sleep(wait_time)

retries = 3

while retries > 0:
    response = elbv2_client.describe_target_health(
        TargetGroupArn=target_group_arn
    )
    healths = map(lambda target: target['TargetHealth']['State'], response['TargetHealthDescriptions'])
    unhealthy = reduce(lambda acc, health: acc + 1 if health != 'healthy' else acc, healths, 0)
    if unhealthy == 0:
        exit(0)
    time.sleep(30.0)
    retries -= 1

exit(1)
