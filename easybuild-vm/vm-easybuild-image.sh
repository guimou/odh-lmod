#!/bin/sh
set -e

################################################################################
# Help                                                                         #
################################################################################
Help()
{
   # Display Help
   echo "Creates a kubevirt compatible VM image that includes easybuild."
   echo "Don't forget to be logged in to the repo before launching the command!"
   echo
   echo "Syntax: vm-image [-b|r|t|h]"
   echo "options:"
   echo "b     Base image in qcow2 format (Fedora/CentOS/RHEL)."
   echo "r     Repository to push the image (e.g. quay.io/your-org/your/repo)."
   echo "t     Image tag (e.g. v1.1)."
   echo "h     Print this Help."
   echo
}

#args
while getopts "b:r:t:h?" option; do
case $option in
    h|\?) # display Help
        Help
        exit;;
    b) BASE_IMAGE=${OPTARG};;
    r) REPO=${OPTARG};;
    t) TAG=${OPTARG};;
    :)
      echo "Missing option argument for -$OPTARG" >&2; exit 1;;
    *)
      echo "Unimplemented option: -$OPTARG" >&2; exit 1;;
    esac
done

if [[ -z $BASE_IMAGE || -z $REPO || -z $TAG ]]; then
    Help
    exit 1
fi

set -x

wget --continue $BASE_IMAGE -O base_image.qcow2

if ! virt-customize --help >/dev/null; then
  sudo yum install -y virt-customize || sudo yum install -y libguestfs-tools-c
fi

virt-customize -a base_image.qcow2 \
  --run-command "adduser easybuild && echo \"easybuild:easybuild\" | chpasswd && usermod -aG wheel easybuild" \
  --install git,tar,which,bzip2,xz,make,automake,gcc,gcc-c++,patch,zlib-devel,openssl-devel,unzip,iproute,file,pam-devel,ant,sudo,lua,lua-devel,lua-posix,lua-filesystem,tcl,python-keyring,http-parser \
  --run-command "yum clean all && \
                mkdir -p /build && \
                cd /build && curl -LO https://github.com/TACC/Lmod/archive/8.4.28.tar.gz && \
                mv /build/8.4.28.tar.gz /build/Lmod-8.4.28.tar.gz && \
                tar xvf Lmod-8.4.28.tar.gz && \
                cd /build/Lmod-8.4.28 && ./configure --prefix=/opt/apps --with-fastTCLInterp=no && \
                make install && \
                rm -rf /build && \
                ln -s /opt/apps/lmod/lmod/init/profile /etc/profile.d/z00_lmod.sh" \
  --selinux-relabel

virt-sysprep -a base_image.qcow2

cat <<END >Dockerfile
FROM kubevirt/container-disk-v1alpha:v0.13.7
ADD base_image.qcow2 /disk/
END
docker build -t $REPO:$TAG .
docker push $REPO:$TAG