#!/bin/bash

function initialise {
  pkg="etcd-health-check"
  etcd_peers_file_path="/etc/sysconfig/etcd-peers"
  etcd_cluster_file_path="/var/lib/etcd2/proxy/cluster"
  etcd_port="2379"
  etcd_path="/v2/members"
  etcd_peers_service="/etc/systemd/system/etcd-peers.service"
  output_file="/home/core/peer_health_status.txt"
  healthy_count="0"
  unhealthy_count="0"
  cut_point="3"
  > $output_file
}


initialise

if [ -f "$etcd_peers_file_path" ]; then
    echo "$pkg: etcd-peers file $etcd_peers_file_path already created, checking health of etcd memebers"

    total_peers=$(cat /etc/sysconfig/etcd-peers | grep "INITIAL_CLUSTER=" |awk '{print gsub(/\yhttp\y/,"")}')
    echo "$pkg: Total number of etcd peers : $total_peers"
    
    while [[ $i -lt $total_peers ]]; do 
      i=$[$i+1]
      peer=$(cat /etc/sysconfig/etcd-peers | grep INITIAL_CLUSTER= | cut -d'/' -f$cut_point | cut -d':' -f1)
      echo "$pkg: peer $i : $peer"
      echo "$pkg: Checking health of peer $i"
      peer_health=$(curl --connect-timeout 10 -s -o /dev/null -w "%{http_code}" http://$peer:$etcd_port$etcd_path) 
      echo "peer $i : $peer response code: $peer_health"

      if [ $peer_health == "200" ]; then
        echo "peer $i ( $peer ) is OK, response code is $peer_health"
        echo "peer $i ( $peer ) is OK, response code is $peer_health" >> $output_file
      else
        echo "peer $i ( $peer ) is CRITICAL, response code is $peer_health"
        echo "peer $i ( $peer ) is CRITICAL, response code is $peer_health" >> $output_file
      fi
      cut_point=$[$cut_point+2]
    done 
    healthy_count=$(cat $output_file | grep "OK" | wc -l)
    unhealthy_count=$(cat $output_file | grep "CRITICAL" | wc -l)

    if [[ $unhealthy_count -gt 0 ]]; then
      if [[ $unhealthy_count == $total_peers ]]; then
        echo "$pkg: $unhealthy_count Unhealthy peers detected, all peers are unhealthy/unreachable"
        echo "$pkg: deleting etcd peers file"
        systemctl stop etcd2
        rm -f $etcd_peers_file_path
        rm -f $etcd_cluster_file_path
        echo "$pkg: running etcd-peers container"
        etcd_asg=$(cat $etcd_peers_service | grep PROXY_ASG | cut -d'"' -f2)
        /usr/bin/docker run --net=host -e PROXY_ASG="$etcd_asg" --rm=true -v /etc/sysconfig/:/etc/sysconfig/ monsantoco/etcd-aws-cluster:latest
        systemctl start etcd2
      fi
    else
      echo "$pkg: All peers are healthy"
    fi
  else
    echo "$pkg: etcd-peers file $etcd_peers_file_path doesn't exist, running  the etcd-peers service/container"
    etcd_asg=$(cat $etcd_peers_service | grep PROXY_ASG | cut -d'"' -f2)
    systemctl stop etcd2
    /usr/bin/docker run --net=host -e PROXY_ASG="$etcd_asg" --rm=true -v /etc/sysconfig/:/etc/sysconfig/ monsantoco/etcd-aws-cluster:latest
    systemctl start etcd2
fi

