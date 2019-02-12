#!/bin/bash
# :MCM 3120 PPA install steps: mcm-3.1.2.tgz should be in the same location
# THIS SCRIPT ONLY WORKS FOR UBUNTU LINUX and assumes arch amd64
# Run it on the ICP Master
# either run as root or as a sub-account with sudo configured for NOPASSWORD prompt
# usage: ./mcmQuick.sh admin Passw0rd

if [ $# -eq 0 ]; then
echo "Usage: $0 user password";
echo "";
echo "example, ./mcmQuick.sh admin Passw0rd ";
echo "";
echo ".-=all options are required=-.";
echo "user = admin should do fine";
echo "password = admin user password, in this stencil is Passw0rd";
echo "";
exit 1;
fi

user=$1
pass=$2

# Get the OS
if [ -f /etc/lsb-release ]; then ubuntu=1; echo "ubuntu found"; else rh=1;  echo "redhat found"; fi

# Determine platform architecture
platform_arch=$(arch); if [ "${platform_arch}" == "x86_64" ] ; then platform_arch="amd64"; fi

# Get the public IP
if [ -z "${t}" ]; then
    if [ $ubuntu ]; then
        inetAddrString=$(ifconfig |grep "inet" |grep -v "inet6" |grep -E 'inet.* 9\.|inet.*\:9\.' | awk '{print $2}');
        indexIp=$(echo "${inetAddrString}" | awk '{print index($0, "9.")}')
        if [ "${indexIp}" -eq 0 ]; then
            inetAddrString=$(ifconfig |grep "inet" |grep -v "inet6" |grep "inet.*172\.16\." | awk '{print $2}');
            indexIp=$(echo "${inetAddrString}" | awk '{print index($0, "172.")}')
        fi
        t=$(echo "${inetAddrString}" | awk -vindexIp=$indexIp '{print substr($0, indexIp)}')
    else
        t=$(ifconfig | awk '/inet /{print $2}' | grep ^9\.)
    fi
fi
echo "target = ${t}"
MASTER_IP=$t

cd ~/Downloads;
# download linux 'cloudctl' CLI from IBM and install
curl -kLo cloudctl-linux-amd64-3.1.2-1203 https://$MASTER_IP:8443/api/cli/cloudctl-linux-amd64; chmod 755 cloudctl-linux-amd64-3.1.2-1203; mv cloudctl-linux-amd64-3.1.2-1203 /usr/local/bin/cloudctl

# download 'helm cli' from your local ICP and install
curl -kLo helm-linux-amd64-v2.9.1.tar.gz https://$MASTER_IP:8443/api/cli/helm-linux-amd64.tar.gz; mkdir helm-unpacked; tar -xvzf ./helm-linux-amd64-v2.9.1.tar.gz -C helm-unpacked/; chmod 755 helm-unpacked/linux-amd64/helm; mv helm-unpacked/linux-amd64/helm /usr/local/bin/helm; rm -rf ./helm-unpacked ./helm-linux-amd64-v2.9.1.tar.gz

# login to your cluster and configure helm cli with ICP certs
cloudctl login -u $user -p $pass --skip-ssl-validation -c id-mycluster-account -a https://$MASTER_IP:8443 -n default

# log in to the Docker private image registry
docker login -u $user -p $pass mycluster.icp:8500

# unpack the MCM archive
tar -xzvf mcm-3.1.2.tgz

# load the mcm-prod PPA archive into kube-system
cloudctl catalog load-ppa-archive -a mcm-3.1.2/mcm-ppa-3.1.2.tgz --registry mycluster.icp:8500/kube-system

# create the mcm-all namespace
kubectl create namespace mcm-all

#grab the MCM chart that was loaded into the repo
wget https://mycluster.icp:8443/helm-repo/requiredAssets/ibm-mcm-prod-3.1.2.tgz --no-check-certificate

# run the MCM deploy
c_echo(){
    RED="\033[0;31m"
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # No Color

    printf "${!1}${2} ${NC}\n"
}

c_echo "RED" "deploying MCM chart on ICP hub cluster; please wait a few minutes..."
c_echo "RED" "expect some output:"
c_echo "RED" "  Error: Job failed: BackoffLimitExceeded"
c_echo "RED" "since we do not have Grafana enabled in this stencil"
helm install ibm-mcm-prod-3.1.2.tgz --name mcm --namespace kube-system --set mcmNamespace=mcm-all --tls

# check the pods status to ensure all are running
watch kubectl get -n kube-system pods -o wide -l release=mcm
