import boto3
import time
import argparse
import sys
from functools import reduce

codedeploy_client = boto3.client('codedeploy')
elbv2_client = boto3.client('elbv2')


class Deployer:

    def __init__(self,
                 retries,
                 application,
                 deployment_group,
                 bucket,
                 bucket_key,
                 bundle_type,
                 target_group_arn):
        self.retries = retries
        self.application = application
        self.deployment_group = deployment_group
        self.bucket = bucket
        self.bucket_key = bucket_key
        self.bundle_type = bundle_type
        self.target_group_arn = target_group_arn

    @staticmethod
    def get_deployment_info(deployment_id):
        return codedeploy_client.get_deployment(deploymentId=deployment_id)['deploymentInfo']

    def get_running_deployments(self):
        response = codedeploy_client.list_deployments(
            applicationName=self.application,
            deploymentGroupName=self.deployment_group,
            includeOnlyStatuses=['InProgress']
        )
        ids = response['deployments']
        return list(map(lambda deployment_id: Deployer.get_deployment_info(deployment_id), ids))

    def wait_for_running(self):
        running = self.get_running_deployments()
        while len(running) > 0:
            for deployment in running:
                print("Running deployment initiated by: {}".format(deployment['creator']))
            print("Waiting for 30 seconds")
            time.sleep(30.0)
            running = self.get_running_deployments()

    @staticmethod
    def get_unhealthy_number(target_group_arn):
        response = elbv2_client.describe_target_health(
            TargetGroupArn=target_group_arn
        )
        healths = map(lambda target: target['TargetHealth']['State'], response['TargetHealthDescriptions'])
        return reduce(lambda acc, health: acc + 1 if health != 'healthy' else acc, healths, 0)

    def wait_target_group_healthy(self):
        unhealthy = Deployer.get_unhealthy_number(self.target_group_arn)
        while unhealthy > 0:
            print("{} ALB instances still unhealthy".format(unhealthy))
            time.sleep(30.0)
            unhealthy = Deployer.get_unhealthy_number(self.target_group_arn)
        print("All instances passed health check")

    @staticmethod
    def wait_for_deployment(deployment_id):
        status = Deployer.get_deployment_info(deployment_id)['status']
        while status not in ['Failed', 'Stopped', 'Succeeded']:
            print("deployment not finished, current status: {}".format(status))
            print("waiting for 30 seconds")
            time.sleep(30.0)
            status = Deployer.get_deployment_info(deployment_id)['status']
        return status

    def deploy(self):
        response = codedeploy_client.create_deployment(
            applicationName=self.application,
            deploymentGroupName=self.deployment_group,
            revision={
                'revisionType': 'S3',
                's3Location': {
                    'bucket': self.bucket,
                    'key': self.bucket_key,
                    'bundleType': self.bundle_type
                }
            }
        )
        deployment_id = response['deploymentId']
        status = self.wait_for_deployment(deployment_id)
        print("deployment finished with status: {}".format(status))
        time.sleep(40.0)
        self.wait_target_group_healthy()


def main():
    parser = argparse.ArgumentParser(description='Deploy App using CodeDeploy')
    parser.add_argument('--retries', default=10)
    parser.add_argument('--application', required=True)
    parser.add_argument('--bucket', required=True)
    parser.add_argument('--bucket-key', required=True)
    parser.add_argument('--bundle-type', default='zip')
    parser.add_argument('--deployment-group', required=True)
    parser.add_argument('--target-group-arn', required=True)
    args = parser.parse_args()
    deployer = Deployer(args.retries,
                        args.application,
                        args.deployment_group,
                        args.bucket,
                        args.bucket_key,
                        args.bundle_type,
                        args.target_group_arn)
    deployer.deploy()


if __name__ == "__main__":
    main()
