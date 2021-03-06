#!/bin/sh
CMD_BASE="$(readlink -f "$0")" || CMD_BASE="$0"; CMD_BASE="$(dirname "$CMD_BASE")"

IMAGE="elifarley/docker-jenkins-uidfv"

docker pull "$IMAGE"

curl -fsL --connect-timeout 1 http://169.254.169.254/latest/meta-data/local-ipv4 >/dev/null && {
  hostname="$(hostname)"
  log_stream_name="$(date +'%Y%m%d.%H%M%S')/$(echo ${hostname%%.*}/${IMAGE##*:} | tr -s ':* ' ';..')"
  log_config="
  --log-driver=awslogs
  --log-opt awslogs-group=/jenkins/master
  --log-opt awslogs-stream=$log_stream_name
  --log-opt awslogs-region=sa-east-1
  "
  echo "Log stream name: $log_stream_name"
  cp -av ~/.ssh/*.p?? "$CMD_BASE"/../mnt-ssh-config/
}

dimg() { docker inspect "$1" |grep Image | grep -v sha256: | cut -d'"' -f4 ;}
dstatus() { docker inspect "$1" | grep Status | cut -d'"' -f4 ;}

drun() {
  local name="$1"; test $# -gt 0 && shift
  local status="$(dstatus "$name" 2>/dev/null)"; echo "Container status for '$name': $status"
  test "$status" = running && echo "STOPPING at $(date)"

  case "$status" in running|restarting|created)
    echo "OLD IMAGE: $(dimg "$name")"
    docker stop >/dev/null -t 30 "$name" && docker >/dev/null rm "$name" || exit
  ;; exited) docker >/dev/null rm "$name" || exit
  ;; '') echo "Container '$name' not found."
  ;; *) echo "Unknown container status: $status"; docker ps | grep "$name"; docker rm -f "$name"
  esac

# --dns=10.11.64.21 --dns=10.11.64.22 --dns-search=m4ucorp.dmc \

  local hostIP="$(curl -fsL --connect-timeout 1 http://169.254.169.254/latest/meta-data/local-ipv4 || hostname -I | cut -d' ' -f1)"

  ( set -x
  docker run -d --restart=always --name "$name" \
-p 8080:8080 -p 50000:50000 -p 9910:9910 -p 9911:9911 \
--add-host=docker-host:$hostIP \
-v "$(readlink -f "$CMD_BASE"/../..)":/var/jenkins_home \
-v "$(readlink -f "$CMD_BASE"/../mnt-ssh-config)":/mnt-ssh-config:ro \
-e JAVA_OPTS="
-Djava.util.logging.config.file="$(readlink -f "$CMD_BASE"/../jenkins-java-util-logging.config)"
-Dcom.sun.management.jmxremote
-Dcom.sun.management.jmxremote.ssl=false
-Dcom.sun.management.jmxremote.authenticate=false
-Dcom.sun.management.jmxremote.port=9910
-Dcom.sun.management.jmxremote.rmi.port=9911
-Djava.rmi.server.hostname=$hostIP
" \
  $log_config \
  "$IMAGE" "$@"
  ) || return

  echo "STARTED at $(date)"
}

drun jenkins
