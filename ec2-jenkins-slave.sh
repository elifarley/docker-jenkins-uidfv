#!/bin/sh

jenkins_slave_setup() {

  test $(id -u) = 0 || {
    echo "--setup must be run as root instead of user '$(id -un)'"; return 1
  }

  _USER=admin

  apt-get update -y && apt-get install -y ca-certificates curl \
  bzip2 mercurial time vim || return

  curl -fsSL https://test.docker.com/ | sh || return
  gpasswd -a "$_USER" docker

  curl -H 'Cache-Control: no-cache' -fsSL https://raw.githubusercontent.com/elifarley/cross-installer/master/install.sh | sh && \
  xinstall save-image-info && \
  xinstall add tar && \
  xinstall add jdk-8-nodesktop && \
  xinstall add maven3 3.3.9 && \
  xinstall add gradle 3.2.1 '6ef2801f1519c2b5f7daa130209cc5e9f0704dfb' && \
  xinstall add shellbasedeps && \
  sudo -u admin xinstall add shellbase 1.0.9 && \
  sudo -u admin xinstall add shellbasevimextra && \
  xinstall cleanup

}

jenkins_slave_compiler_setup() {

  jenkins_slave_setup || return

  APT_PACKAGES="\
gcc g++ make patch binutils libc6-dev \
  libjemalloc-dev libffi-dev libssl-dev libyaml-dev zlib1g-dev libgmp-dev libxml2-dev \
  libxslt1-dev libreadline-dev libsqlite3-dev \
  libpq-dev unixodbc unixodbc-dev unixodbc-bin ruby-odbc freetds-bin freetds-common freetds-dev postgresql-client \
  git lxc\
" xinstall add-pkg && xinstall cleanup

}

id
set -x
export DEBUG=1

test "$1" = '--setup' -o -n "$SETUP" && {
  jenkins_slave_setup
  exit
}

test "$1" = '--setup-compiler' -o -n "$SETUP_COMPILER" && {
  jenkins_slave_compiler_setup
  exit
}

# export COMPANY=my-company SETUP=1; curl -H 'Cache-Control: no-cache' -fsSL \
# https://raw.githubusercontent.com/elifarley/docker-jenkins-uidfv/master/ec2-jenkins-slave.sh \
# | sh

#--- Jenkins Amazon EC2 Cloud Plugin - Init Script:

COMPANY="${1:-$COMPANY}"
JENKINS_SLAVE_EMAIL="${2:-jenkins-slave@$COMPANY.com}"

test "$COMPANY" || { echo "COMPANY not set."; return 1 ;}

test -d /app -o -L /app || {
  sudo ln -s ~/app /app || exit
}

mkdir -p ~/app ~/.ssh || exit

cat <<-EOF >> ~/.hgrc || exit
[ui]
username = Jenkins Slave <$JENKINS_SLAVE_EMAIL>
EOF

cat <<-EOF >> ~/.ssh/config || exit
Host bitbucket.org
  IdentityFile ~/.ssh/${COMPANY}robot@bitbucket.pem
  IdentitiesOnly yes
  User git
EOF

aws s3 --quiet cp s3://$COMPANY.jenkins/mnt-ssh-config/known_hosts /dev/stdout | cat >> ~/.ssh/known_hosts && \
aws s3 cp s3://$COMPANY.jenkins.secrets/${COMPANY}robot@bitbucket.pem ~/.ssh/ || exit

chmod 0700 ~/.ssh && \
chmod 0400 ~/.ssh/* &&
chmod u+w ~/.ssh/known_hosts || exit
for k in ~/.ssh/*.pub; do
  test -e "$k" && chmod a+r "$k"
done

# --

HG_URL="ssh://hg@bitbucket.org/elifarley/$COMPANY.jenkins-slave.config"

if test -d ~/jenkins-slave.config/.hg; then
  hg --cwd ~/jenkins-slave.config pull && hg --cwd ~/jenkins-slave.config up -C
else
  echo "Cloning repository '$HG_URL' to '$HOME/jenkins-slave.config'..."
  hg clone "$HG_URL" ~/jenkins-slave.config || exit
fi

mkdir -p ~/.m2 ~/.gradle ~/.docker && ( cd ~/jenkins-slave.config && \
chmod go= mvn-settings.xml gradle.properties docker-config.json && \
cp -av mvn-settings.xml ~/.m2/settings.xml && \
cp -av gradle.properties ~/.gradle/gradle.properties && \
cp -av docker-config.json ~/.docker/config.json ) || exit

sudo JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/default-jvm}" /usr/local/bin/keytool-import-certs --force ~/jenkins-slave.config/mnt-ssh-config/certs
