import boto3
import time
import argparse
from functools import reduce

codedeploy_client = boto3.client('codedeploy')
elbv2_client = boto3.client('elbv2')


class DeploymentStoppedError(Exception):
    pass


class DeploymentFailedError(Exception):
    pass


class NumberOfRetriesExceededError(Exception):
    pass


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

    def deploy_s3_bundle(self):
        return codedeploy_client.create_deployment(
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

    def deploy(self):
        counter = 0
        finished = False
        while not (counter == self.retries or finished):
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
