## This script is intended to be run on Ubuntu 16.04 LTS or 18.04 LTS
## as an automated way to install basic RCloud without metadata services
## mainly to boostrap compute note VMs
##
## Author: Simon Urbanek <simon.urbanek@R-project.org>
## License: MIT

META_IP=172.31.1.116
RCUSER=rcloud

## internal IP address - we know it starts with 172...
HOST=`/sbin/ifconfig  | sed -n 's:.*inet 172:172:p' | sed 's: .*::'`
export HOST

## add  R3.5 repo
sudo add-apt-repository -y ppa:marutter/rrutter3.5
sudo apt-get update

## install dependencies
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y gcc g++ gfortran libcairo-dev libreadline-dev libxt-dev libjpeg-dev \
libicu-dev libssl-dev libcurl4-openssl-dev subversion git automake make libtool \
 libtiff-dev gettext redis-server rsync curl libxml2-dev python-dev r-base-dev \
 emacs25-nox nfs-common

## jupyter support
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y jupyter python-ipython python-ipykernel python-nbconvert python-nbformat python-jupyter-client python-jupyter-core 

## create RCloud user
sudo useradd -m -U -s /bin/bash $RCUSER

## we install everything in /data -- could be a volume or create it
if [ ! -e /data ]; then
  sudo mkdir /data
  sudo chown $RCUSER /data
fi

## we don't want to be installing anything as root, so make sure
## the current admin user can write in the local site library
SITELIB=`Rscript -e 'cat(.libPaths()[1])'`
sudo chown $RCUSER "$SITELIB"

## fixed for now .. we don't have a dynamic way to discover the meta server yet...
if grep rc-meta /etc/hosts; then
    echo "rc-meta already set, not touching"
else
    echo "Adding ${META_IP} to /etc/hosts as rc-meta"
    sudo sh -c "echo ${META_IP} rc-meta >> /etc/hosts"
fi

## this is not needed for released versions, but is needed for devel checkouts
## due to a bug in Ubuntu 18.04 just installing npm breaks so this is a work-around
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs=8.10.0~dfsg-2ubuntu0.2 nodejs-dev=8.10.0~dfsg-2ubuntu0.2 npm

export ROOT=/data/rcloud

sudo -i -u rcloud bash <<EOBASH

## ok, now get RCloud sources
cd /data
git clone https://github.com/att/rcloud.git
cd rcloud
export ROOT=/data/rcloud

mkdir tmp run
chmod 0777 tmp run
ln -s data/Rlib Rlib

## need 0777 for user-switching
sed -i 's:sockmod 0770:sockmod 0777:' conf/rserve-proxified.conf

## install all RCloud dependencies
MAKEFLAGS=-j6 sh scripts/bootstrapR.sh

echo Installing Node packages...
## install notejs modules needed in RCloud
npm install

## build all packages and artifacts
sh scripts/build.sh

## also the host is assumed to have `rc-meta` entry in `/etc/hosts`
## for the metadata server
## Create a configuration file with user authentication (SKS using PAM),
## and using gist service:
cat > conf/rcloud.conf <<EOF
Host: $HOST
Cookie.Domain: rcloud.social
github.client.id: X
github.client.secret: X
github.base.url: https://github.com/
github.api.url: https://api.github.com/
github.gist.url: https://gist.github.com/
use.gist.user.home: yes
rcs.engine: redis
rcs.redis.host: rc-meta:6990
solr.url: http://rc-meta:8983/solr/rcloudnotebooks
Welcome.page: /rcloud.html
Welcome.info: on `hostname`
session.server: http://rc-meta:4301
rcs.system.config.featured_users: rclouddocs
rcloud.alluser.addons: rcloud.viewer, rcloud.enviewer, rcloud.notebook.info, rcloud.htmlwidgets, rcloud.rmd, rcloud.flexdashboard, rcloud.jupyter.notebooks, rcloud.shiny
rcloud.languages: rcloud.r, rcloud.rmarkdown, rcloud.sh, rcloud.jupyter
rserve.socket: \${ROOT}/run/qap
compute.separation.modes: IDE
EOF

EOBASH


## mount EFS

sudo mkdir /data/rcloud/data
sudo chown $RCUSER /data/rcloud/data

echo Mounting EFS RCloud.home ...
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,noatime,retrans=2,noresvport fs-99cd9ce0.efs.us-east-2.amazonaws.com:/ /data/rcloud/data/
echo done

## add -S rc-meta to the proxy; this roundabout way is to avoid sudo quoting hell for the regexp...
echo 'sed -i '"'"'s:^\(exec.*\)$:\1 -S rc-meta:'"'"' /data/rcloud/services/rcloud-proxy' > /tmp/1
sudo -u rcloud sh /tmp/1
rm /tmp/1

## NOTE: you can run the srvmgr on the nginx node something like this:
## srvmgr -v -p 40 -r '/etc/init.d/nginx reload' -c /mnt/etc/nginx-servers -m 172.31.0.0/20

sudo -i -u rcloud bash <<EOBASH                                                                                                                                                                              
cd /data/rcloud
echo === Starting QAP ...
sh scripts/fresh_start.sh --no-build
echo === Starting scripts ...
sh services/rcloud-script-start
echo === Starting proxy ...
nohup services/rcloud-proxy &

echo === DONE ===
EOBASH

# this is more secure but for a public instance it may be better to run everything as rcloud...

#sudo useradd rcscr -m -U 

## create all users defined in the metadata server
#users=`Rscript -e 'cat(rediscc::redis.get(rediscc::redis.connect("rc-meta",6990), ".meta.users"))'`
#for user in $users; do
#  sudo useradd -m -U $user
#done
