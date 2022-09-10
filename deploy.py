import boto3
import time
import argparse

codedeploy_client = boto3.client('codedeploy')
elbv2_client = boto3.client('elbv2')
asg_client = boto3.client('autoscaling')
ec2_client = boto3.client('ec2')


class DeploymentStoppedError(Exception):
    pass


class DeploymentFailedError(Exception):
    pass


class NumberOfRetriesExceededError(Exception):
    pass


class RefreshCancelledOrFailedError(Exception):
    pass


class Deployer:

    def __init__(self,
                 retries,
                 application,
                 deployment_group,
                 bucket,
                 bucket_key,
                 bundle_type,
                 target_group_arn,
                 classic_lb_name):
        self.retries = retries
        self.application = application
        self.deployment_group = deployment_group
        self.bucket = bucket
        self.bucket_key = bucket_key
        self.bundle_type = bundle_type
        self.target_group_arn = target_group_arn
        self.classic_lb_name = classic_lb_name

    @staticmethod
    def get_deployment_info(deployment_id):
        return codedeploy_client.get_deployment(deploymentId=deployment_id)['deploymentInfo']

    def get_deployment_group_info(self):
        return codedeploy_client.get_deployment_group(applicationName=self.application,
                                                      deploymentGroupName=self.deployment_group)['deploymentGroupInfo']

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

    def wait_for_deployment(self, deployment_id):
        status = Deployer.get_deployment_info(deployment_id)['status']
        counter = 0
        while status not in ['Failed', 'Stopped', 'Succeeded']:
            if counter == self.retries:
                raise NumberOfRetriesExceededError
            print("deployment not finished, current status: {}".format(status))
            print("waiting for 30 seconds")
            time.sleep(30.0)
            status = Deployer.get_deployment_info(deployment_id)['status']
            counter += 1
        return status

    def deploy_s3_bundle(self, green_asg=None):
        args = {
            'applicationName': self.application,
            'deploymentGroupName': self.deployment_group,
            'revision': {
                'revisionType': 'S3',
                's3Location': {
                    'bucket': self.bucket,
                    'key': self.bucket_key,
                    'bundleType': self.bundle_type
                }
            }
        }
        if green_asg is not None:
            args['targetInstances'] = {
                'autoScalingGroups': [green_asg]
            }
        return codedeploy_client.create_deployment(**args)

    def is_blue_green(self):
        return self.get_deployment_group_info()['deploymentStyle']['deploymentType'] == "BLUE_GREEN"

    def get_current_asg(self):
        info = self.get_deployment_group_info()
        return info["autoScalingGroups"][0]['name']

    def get_blue_asg(self):
        current_asg = self.get_current_asg()
        groups = self.get_autoscaling_groups()
        return list(filter(lambda group: group != current_asg, groups))[0]

    def get_autoscaling_groups(self):
        response = asg_client.describe_auto_scaling_groups(
            Filters=[
                {
                    'Name': 'tag:Name',
                    'Values': [self.application]
                }
            ]
        )
        return list(map(lambda group: group['AutoScalingGroupName'], response['AutoScalingGroups']))

    def choose_asg(self):
        current_group_name = self.get_current_asg()
        names = self.get_autoscaling_groups()
        first = names[0]
        second = names[1]
        print("Current group: {}".format(current_group_name))
        if current_group_name == first:
            print("Chosen group: {}".format(second))
            return second
        else:
            print("Chosen group: {}".format(first))
            return first

    def terminate_blue_instances(self):
        blue_asg = self.get_blue_asg()
        asg_info = asg_client.describe_auto_scaling_groups(AutoScalingGroupNames=[blue_asg])['AutoScalingGroups'][0]
        instance_ids = list(map(lambda instance: instance['InstanceId'], asg_info['Instances']))
        ec2_client.terminate_instances(InstanceIds=instance_ids)
        print("Blue ASG instances termination initialized")

    def deploy(self):
        counter = 0
        finished = False
        while not (counter == self.retries or finished):
            if self.is_blue_green():
                print("Blue/Green deployment detected")
                asg_name = self.choose_asg()
                deployment_id = self.deploy_s3_bundle(green_asg=asg_name)['deploymentId']
            else:
                deployment_id = self.deploy_s3_bundle()['deploymentId']
            status = self.wait_for_deployment(deployment_id)
            if status == 'Failed':
                error_info = Deployer.get_deployment_info(deployment_id)['errorInformation']
                print('Deployment failed. Reason: {}'.format(error_info['message']))
                if error_info['code'] == 'NO_INSTANCES':
                    counter += 1
                else:
                    raise DeploymentFailedError
            elif status == 'Succeeded':
                print("deployment finished with status: {}".format(status))
                # self.wait_target_group_healthy()
                finished = True
            else:
                raise DeploymentStoppedError
        if self.is_blue_green():
            self.terminate_blue_instances()

    def wait_for_instances_refresh(self):
        names = self.get_autoscaling_groups()
        running = set({})
        for name in names:
            refreshes = asg_client.describe_instance_refreshes(AutoScalingGroupName=name)['InstanceRefreshes']
            for refresh in refreshes:
                status = refresh['Status']
                refresh_id = refresh['InstanceRefreshId']
                if status in ['Pending', 'InProgress']:
                    print("Refresh {} status: {}".format(refresh_id, status))
                    running.add((refresh_id, name))
        finished = set({})
        counter = 0
        while not (counter == self.retries or running - finished == set({})):
            for (refresh, name) in running:
                response = asg_client.describe_instance_refreshes(AutoScalingGroupName=name,
                                                                  InstanceRefreshIds=[refresh])
                refresh_info = response['InstanceRefreshes'][0]
                status = refresh_info['Status']
                if status == 'Successful':
                    print("Refresh {} finished".format(refresh))
                    finished.add((refresh, name))
                elif status in ['Pending', 'InProgress']:
                    print("Refresh {} status: {}".format(refresh, status))
                else:
                    raise RefreshCancelledOrFailedError
            print("waiting for 30 seconds")
            counter += 1
            time.sleep(30.0)


def main():
    parser = argparse.ArgumentParser(description='Deploy App using CodeDeploy')
    parser.add_argument('--retries', default=10)
    parser.add_argument('--application', required=True)
    parser.add_argument('--bucket', required=True)
    parser.add_argument('--bucket-key', required=True)
    parser.add_argument('--bundle-type', default='zip')
    parser.add_argument('--deployment-group', required=True)
    parser.add_argument('--target-group-arn')
    parser.add_argument('--classic-lb-name')
    args = parser.parse_args()
    deployer = Deployer(args.retries,
                        args.application,
                        args.deployment_group,
                        args.bucket,
                        args.bucket_key,
                        args.bundle_type,
                        args.target_group_arn,
                        args.classic_lb_name)
    deployer.wait_for_instances_refresh()
    deployer.deploy()


if __name__ == "__main__":
    main()
