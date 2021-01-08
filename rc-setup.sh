## This script is intended to be run on Ubuntu 16.04 LTS or 18.04 LTS
## as an automated way to install basic RCloud without metadata services
## mainly to boostrap compute note VMs
##
## Author: Simon Urbanek <simon.urbanek@R-project.org>
## License: MIT

META_IP=172.31.13.33

## add  R3.5 repo
sudo add-apt-repository -y ppa:marutter/rrutter3.5
sudo apt-get update

## install dependencies
sudo apt-get install -y gcc g++ gfortran libcairo-dev libreadline-dev libxt-dev libjpeg-dev \
libicu-dev libssl-dev libcurl4-openssl-dev subversion git automake make libtool \
 libtiff-dev gettext redis-server rsync curl libxml2-dev python-dev r-base-dev \
 emacs25-nox

## jupyter support
sudo apt-get install -y jupyter python-ipython python-ipykernel python-nbconvert python-nbformat python-jupyter-client python-jupyter-core 

## we install everything in /data -- could be a volume or create it
if [ ! -e /data ]; then
  sudo mkdir /data
  sudo chown $USER /data
fi

## we don't want to be installing anything as root, so make sure
## the current admin user can write in the local site library
SITELIB=`Rscript -e 'cat(.libPaths()[1])'`
sudo chown $USER "$SITELIB"

## ok, now get RCloud sources
cd /data
git clone https://github.com/att/rcloud.git
cd rcloud

## install all RCloud dependencies
sh scripts/bootstrapR.sh

## this is not needed for released versions, but is needed for devel checkouts
## due to a bug in Ubuntu 18.04 just installing npm breaks so this is a work-around
sudo apt-get install -y npm node-gyp nodejs-dev libssl1.0-dev
## install notejs modules needed in RCloud
npm install

## build all packages and artifacts
sh scripts/build.sh

## NOTE: $HOST must be set to the externally visible hostname or IP-address
if [ -z "$HOST" ]; then HOST=`curl -s http://checkip.amazonaws.com/`; fi

## also the host is assumed to have `rc-meta` entry in `/etc/hosts`
## for the metadata server
## Create a configuration file with user authentication (SKS using PAM),
## and using gist service:
cat > conf/rcloud.conf <<EOF
Host: $HOST
github.api.url: http://rc-meta:13020/
rcs.engine: redis
rcs.redis.host: rc-meta:6990
solr.url: http://rc-meta:8983/solr/rcloudnotebooks
Exec.auth: pam
Exec.match.user: login
Exec.anon.user: nobody
HTTP.user: www-data
Welcome.page: /rcloud.html
github.client.id: default
github.client.secret: X
session.server: http://rc-meta:4301
github.auth: exec.token
github.auth.forward: /login_successful.R
rcloud.alluser.addons: rcloud.viewer, rcloud.enviewer, rcloud.notebook.info, rcloud.htmlwidgets, rcloud.rmd, rcloud.flexdashboard, rcloud.jupyter.notebooks, rcloud.shiny
rcloud.languages: rcloud.r, rcloud.rmarkdown, rcloud.sh, rcloud.jupyter
rserve.socket: \${ROOT}/run/qap
compute.separation.modes: IDE
rational.githubgist: true
EOF

mkdir tmp run
sudo chmod 0777 tmp run

## need 0777 for user-switching
sed -i 's:sockmod 0770:sockmod 0777:' conf/rserve-proxified.conf

sudo useradd rcscr -m -U 

## fixed for now .. we don't have a dynamic way to discover the meta server yet...
sudo sh -c "echo ${META_IP} rc-meta >> /etc/hosts"

## create all users defined in the metadata server
users=`Rscript -e 'cat(rediscc::redis.get(rediscc::redis.connect("rc-meta",6990), ".meta.users"))'`
for user in $users; do
  sudo useradd -m -U $user
done

echo ## to start script service
echo sudo services/rcloud-script
echo sudo su - rcscr /data/rcloud/services/rcloud-proxy 
