"""Activities for interfacing with gcloud"""
import os

from xonsh.tools import print_color

from rever.activity import Activity


def _ensure_default_credentials():
    credfile = os.path.join($XDG_CONFIG_HOME, 'gcloud', 'application_default_credentials.json')
    if os.path.isfile(credfile):
        print_color('{YELLOW}Found ' + credfile + ' ...{NO_COLOR}')
    else:
        ![gcloud auth application-default login]
    $CLOUDSDK_CONTAINER_USE_APPLICATION_DEFAULT_CREDENTIALS = 'true'
    return credfile


def _ensure_account(n=0):
    if n > 3:
        raise RuntimeError('failed to log in to gcloud')
    account = $(gcloud config get-value account).strip()
    if account == '(unset)' or '@' not in account:
        n += 1
        print(f'gcloud account is {account}, login attempt {n}/3:')
        ![gcloud auth login]
        account = _ensure_account(n+1)
    return account


class DeployToGCloud(Activity):
    """Deploys a docker container to the google cloud

    This activity may be configured with the following environment variables:

    :$GCLOUD_PROJECT_ID: str, the gcloud project id
    :$GCLOUD_ZONE: str, the gcloud zone
    :$GCLOUD_CLUSTER: str the kubernetes cluster to deploy to
    :$GCLOUD_CONTAINER_NAME: str, the name of the container image to deploy to
    :$GCLOUD_DOCKER_ORG: str, the name of the docker org to pull the container
        from
    :$GCLOUD_DOCKER_REPO: str, the name of the docker container repo to use
    :$VERSION: str, the version of the container to use
    """

    def __init__(self, *, deps=frozenset()):
        super().__init__(name='deploy_to_gcloud', deps=deps, func=self._func,
                         desc="Deploys a docker container to the google cloud",
                         check=self.check_func)
    def check_func(self):
        clis = [
            ('gcloud', 'google-cloud-sdk'),
            ('kubectl', 'kubernetes'),
            ]
        bad = []
        for cli, package in clis:
            if not !(which @(cli)):
                bad.append((cli, package))
        if bad:
            s = ''
            for cli, package in bad:
                s += f'Could not find {cli}! Try installing:\n  $ conda install {package}'
            print(s)
            raise RuntimeError(s)

        # make sure we are logged in
        _ensure_default_credentials()
        account = _ensure_account()

    def _func(self, project_id, cluster, zone, container_name, docker_org,
              docker_repo):
        """Deploys the build docker containter to the google cloud"""
        # make sure we are logged in
        _ensure_default_credentials()
        account = _ensure_account()
        # get cluster credentials
        ![gcloud container clusters get-credentials --account @(account) \
          --zone=$GCLOUD_ZONE --project=$GCLOUD_PROJECT_ID $GCLOUD_CLUSTER]
        # set new image
        ![kubectl set image deployment/$GCLOUD_CONTAINER_NAME $GCLOUD_CONTAINER_NAME=docker.io/$GCLOUD_DOCKER_ORG/$GCLOUD_DOCKER_REPO:$VERSION]


class DeployTOGCloudApp(Activity):
    """Deploys an app to the google cloud via the app engine

        This activity may be configured with the following environment variables:

        :$GCLOUD_PROJECT_ID: str, the gcloud project id
        :$GCLOUD_ZONE: str, the gcloud zone
        """

    def __init__(self, *, deps=frozenset()):
        super().__init__(name='deploy_to_gcloud_app', deps=deps, func=self._func,
                         desc="Deploys an app to the google cloud via the app engine",
                         check=self.check_func)
    def check_func(self):
        clis = [
            ('gcloud', 'google-cloud-sdk'),
            ]
        bad = []
        for cli, package in clis:
            if not !(which @(cli)):
                bad.append((cli, package))
        if bad:
            s = ''
            for cli, package in bad:
                s += f'Could not find {cli}! Try installing:\n  $ conda install {package}'
            print(s)
            raise RuntimeError(s)
        # make sure we are logged in
        _ensure_default_credentials()
        account = _ensure_account()

    def _func(self, project_id, zone):
        """Deploys the build docker containter to the google cloud"""
        # make sure we are logged in
        _ensure_default_credentials()
        account = _ensure_account()
        ![gcloud app deploy app.yaml index.yaml --account @(account) \
          --zone=$GCLOUD_ZONE --project=$GCLOUD_PROJECT_ID $GCLOUD_CLUSTER]