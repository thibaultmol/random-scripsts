#!/bin/bash

# Check for sudo
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root"
  exit 1
fi

# Check if required tools are installed
for cmd in upower docker tmux; do
  if ! command -v $cmd &> /dev/null; then
    echo "$cmd is not installed. Please install it before running this script."
    exit 1
  fi
done

# Configuration variables
ARCHIVETEAM_BASE_URL="atdr.meo.ws/archiveteam"

# Grabber configurations - format: "grabber_name:instances"
GRABBER_CONFIG=(
  "imgur-grab:1"
  "urls-grab:19"
  "reddit-grab:2"
  "telegram-grab:4"
  "mediafire-grab:1"
  "youtube-grab:1"
  "pixiv-2-grab:1"
)

# Check if Watchtower is running and create it if it doesn't exist
WATCHTOWER_CONTAINER_NAME="watchtower"
WATCHTOWER_IMAGE="containrrr/watchtower"
if ! docker ps -a --filter "name=$WATCHTOWER_CONTAINER_NAME" | grep -q "$WATCHTOWER_CONTAINER_NAME"; then
    echo "Watchtower container doesn't exist. Creating and starting..."
    docker run -d \
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

    # If container exists, delete it
    if docker ps -a --filter "name=$container_name" | grep -q "$container_name"; then
      echo "Container $container_name exists. Deleting..."
      docker rm -f $container_name
    fi

    echo "Creating and starting container $container_name..."
    docker run -d --name $container_name --label=com.centurylinklabs.watchtower.enable=true --cpu-shares 512 $grabber_image --concurrent 20 Thibaultmol 2>&1

    sleep 3  # Add a pause between creating and attaching to the Docker containers

    # Create a new tmux window or split the existing one for each container
    tmux split-window -d -v -t "grabbers" "echo $container_name && docker logs -f $container_name"
    tmux select-layout -t "grabbers" tiled
  done
}

function is_on_ac_power() {
  if command -v upower &> /dev/null; then
    local ac_status=$(upower -i $(upower -e | grep 'BAT') | grep 'state' | awk '{print $2}')
    [[ $ac_status == 'discharging' ]] && return 1 || return 0
  else
    return 0
  fi
}

function suspend_grabbers() {
  for config in "${GRABBER_CONFIG[@]}"; do
    local grabber_name=${config%:*}
    local grabber_instances=${config#*:}

    for i in $(seq 1 $grabber_instances); do
      local container_name="${grabber_name}-${i}"
      docker pause $container_name
    done
  done
}

function resume_grabbers() {
  for config in "${GRABBER_CONFIG[@]}"; do
    local grabber_name=${config%:*}
    local grabber_instances=${config#*:}

    for i in $(seq 1 $grabber_instances); do
      local container_name="${grabber_name}-${i}"
      docker unpause $container_name
    done
  done
}

# Create a new tmux session
tmux new-session -d -s "grabbers"

# Deploy all grabbers
for config in "${GRABBER_CONFIG[@]}"; do
  deploy_grabber ${config%:*} ${config#*:}
done

# Attach to the grabbers tmux session
tmux attach-session -t "grabbers"

# Check power source and suspend/resume Docker containers
while true; do
  if is_on_ac_power; then
    resume_grabbers
  else
    suspend_grabbers
  fi
  sleep 10
done
