#!/bin/bash

# Check for sudo
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script with sudo"
  exit 1
fi

# Configuration variables
ARCHIVETEAM_BASE_URL="atdr.meo.ws/archiveteam"

# Grabber configurations - format: "grabber_name:instances"
GRABBER_CONFIG=(
  "imgur-grab:8"
  "urls-grab:4"
  "reddit-grab:1"
  "telegram-grab:2"
)

HOME_DIR=$(eval echo ~${SUDO_USER})
LOG_DIR="$HOME_DIR/scripts/logs"

# Create the log directory if it doesn't exist
mkdir -p $LOG_DIR

# Check if Watchtower is running and create it if it doesn't exist
WATCHTOWER_CONTAINER_NAME="watchtower"
WATCHTOWER_IMAGE="containrrr/watchtower"
if ! sudo docker ps -a --filter "name=$WATCHTOWER_CONTAINER_NAME" | grep -q "$WATCHTOWER_CONTAINER_NAME"; then
    echo "Watchtower container doesn't exist. Creating and starting..."
    sudo docker run -d \
      --name $WATCHTOWER_CONTAINER_NAME \
      -v /var/run/docker.sock:/var/run/docker.sock \
      $WATCHTOWER_IMAGE
else
    echo "Watchtower container exists. No need to create it."
fi


function deploy_grabber() {
  local grabber_name="$1"
  local grabber_instances="$2"

  for i in $(seq 1 $grabber_instances); do
    local container_name="${grabber_name}-${i}"
    local grabber_image="$ARCHIVETEAM_BASE_URL/$grabber_name"

    if ! sudo docker ps -a --filter "name=$container_name" | grep -q "$container_name"; then
      echo "Container $container_name doesn't exist. Creating and starting..."
      sudo docker run -d --name $container_name --label=com.centurylinklabs.watchtower.enable=true $grabber_image --concurrent 20 Thibaultmol 2>&1 | tee -a $LOG_DIR/Archive${grabber_name}_${i}.log > /dev/null
    else
      echo "Container $container_name exists. Watchtower will handle updates."
    fi
  done
}

for config in "${GRABBER_CONFIG[@]}"; do
  IFS=':' read -ra grabber <<< "$config"
  grabber_name="${grabber[0]}"
  grabber_instances="${grabber[1]}"
  deploy_grabber "$grabber_name" "$grabber_instances"
done
