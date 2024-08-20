#!/usr/bin/env bash
CURRENT_DIR=$(dirname $0)
source "$CURRENT_DIR"/logger.sh

[[ -n "$TRACE" ]] && DEBUG=1 && REDIRECT_TRACE="/dev/stderr" || REDIRECT_TRACE="/dev/null"
[[ -n "$DEBUG" ]] && REDIRECT_DEBUG="/dev/stderr" || REDIRECT_DEBUG="/dev/null"

BASE_IMAGES_FILE="$CURRENT_DIR"/base_images.txt
RUNNING_CONTAINERS_FILE="/run/user/$(id -u)/ansible-tests-containers"
DEFAULT_PLAYBOOK="bootstrap.yml"
REPORT_FILE="/tmp/ansible-tests-report.txt"
echo -n > "$REPORT_FILE"


RETVAL=0

ALL=true
SETUP=false
BOOTSTRAP=false
TESTS=false
REPEAT=false
TEARDOWN=false
REMOTE=false
LOCAL=false
REUSE=false

ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --setup)
      ALL=false
      SETUP=true
      shift
      ;;
    --bootstrap)
      ALL=false
      BOOTSTRAP=true
      shift
      ;;
    --test|--tests)
      ALL=false
      TESTS=true
      shift
      ;;
    --repeat)
      ALL=false
      REPEAT=true
      shift
      ;;
    --teardown)
      ALL=false
      TEARDOWN=true
      shift
      ;;
    --remote)
      REMOTE=true
      shift
      ;;
    --local)
      LOCAL=true
      shift
      ;;
    --reuse)
      REUSE=true
      shift
      ;;
    --base-image*)
      [[ $1 == --base-image=* ]] && BASE_IMAGE="${1#*=}" && shift ||
      BASE_IMAGE="$2" && shift 2
      ;;
    --*)
      error "Unknown option: $1" >&2
      exit 22
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
  esac
done

if $ALL; then
  SETUP=true
  BOOTSTRAP=true
  LOCAL=true
  REMOTE=true
  TESTS=true
  REPEAT=true
  TEARDOWN=true
fi
if $SETUP && ! $LOCAL && ! $REMOTE; then
  error "At least one of --local or --remote must be specified." >&2
  exit 22
fi

set -- "${ARGS[@]}"

playbook="${1:-$DEFAULT_PLAYBOOK}"
containers=()

launch_containers() {
  readarray -t base_images <<< "${BASE_IMAGE:-$(sed '/^#/d' "$BASE_IMAGES_FILE")}"
  for base_image in "${base_images[@]}"; do
    debug "Building image from $base_image..." >&2

    image="ansible-tests-$base_image"
    docker build --build-arg BASE_IMAGE="$base_image" --tag "$image" "$CURRENT_DIR" &> "$REDIRECT_TRACE"
    if [ $? -ne 0 ]; then
      error "Failed to build image from $base_image." >&2
      return 1
    fi

    if $LOCAL; then
      container=$(docker run --rm --detach "$image")
      if [ $? -ne 0 ]; then
        error "Failed to launch container from $image." >&2
        return 1
      fi

      debug "Container launched." >&2

      echo "$container LOCAL" >> "$RUNNING_CONTAINERS_FILE"
      containers+=("$container LOCAL")
    fi
    if $REMOTE; then
      container=$(docker run --rm --detach "$image")
      if [ $? -ne 0 ]; then
        error "Failed to launch container from $image." >&2
        return 1
      fi

      debug "Container launched." >&2

      echo "$container REMOTE" >> "$RUNNING_CONTAINERS_FILE"
      containers+=("$container REMOTE")
    fi
  done

  total_containers=${#containers[@]}
  if [ $total_containers -eq 0 ]; then
    error "No containers launched." >&2
    return 1
  else
    success "Containers launched: $total_containers" >&2
  fi

}

docker_ip() {
  container="$1"
  docker inspect -f '{{.NetworkSettings.IPAddress}}' "$container"
}

docker_image() {
  container="$1"
  image_sha=$(docker inspect "$container" | jq -r '.[0].Config.Image')
  image_name=$(docker image inspect "$image_sha" | jq -r '.[0].RepoTags[0]')
  echo "$image_name"
}

bootstrap() {
  container="$1"
  docker cp . "$container":/ansible
  debug "Executing bootstrap playbook on docker localhost..." >&2
  docker exec --workdir /ansible --tty "$container" ansible-playbook ${TRACE:+"-vv"} --user test --connection local --inventory localhost, "$playbook" &> "$REDIRECT_DEBUG"
  if [ $? -ne 0 ]; then
    error "Bootstrap playbook failed." >&2
    RETVAL=1
    return 1
  fi
}

bootstrap_remote() {
  ip="$1"
  debug "Executing bootstrap playbook on remote..." >&2
  ansible-playbook --inventory "$ip," ${TRACE:+"-vv"} --user test --private-key "$CURRENT_DIR"/.ssh/id_rsa "$playbook" &> "$REDIRECT_DEBUG"
  if [ $? -ne 0 ]; then
    error "Bootstrap playbook failed." >&2
    RETVAL=1
    return 1
  fi
}

run_tests() {
  container="$1"
  image=$(docker_image "$container")

  all_tests_passed=true
  for file in "$CURRENT_DIR"/test_*.sh; do
    debug "Running $file..." >&2
    docker exec -i "$container" bash -l < "$file" &> "$REDIRECT_DEBUG"
    if [ $? -ne 0 ]; then
      warn "Test $file failed." >&2
      all_tests_passed=false
      RETVAL=1
      report "$REPORT_FILE" "    $file" "FAILED"
    else
      report "$REPORT_FILE" "    $file" "PASSED"
    fi
  done

  if $all_tests_passed; then
    success "All tests passed in $image." >&2
  else
    error "Some tests failed in $image." >&2
  fi
}

teardown() {
  all_containers_stopped=true

  readarray -t running_containers < "$RUNNING_CONTAINERS_FILE"
  for container_line in "${running_containers[@]}"; do
    read -r container type <<< "$container_line"
    # first cleanup dangling containers
    if ! docker inspect "$container" &> /dev/null; then
      debug "Removing dangling container $container..." >&2
      sed --in-place "/$container/d" "$RUNNING_CONTAINERS_FILE"
      continue
    fi

    debug "Stopping container $container..." >&2

    if docker stop "$container" > /dev/null; then
      sed --in-place "/$container/d" "$RUNNING_CONTAINERS_FILE"
    else
      error "Failed to stop container $container" >&2
      all_containers_stopped=false
      RETVAL=2
    fi
  done

  if $all_containers_stopped; then
    success "Teardown successful" >&2
  else
    error "Teardown failed" >&2
  fi
}


main() {
  if $SETUP; then
    info "Running setup..." >&2

    launch_containers
  fi


  if [ $? -eq 0 ]; then

    if $REUSE; then
      info "Reusing running containers..." >&2
      if [ -f "$RUNNING_CONTAINERS_FILE" ]; then
        readarray -t containers < "$RUNNING_CONTAINERS_FILE"
      fi
      debug "Total containers: ${#containers[@]}" >&2
    fi

    if $LOCAL; then
      info "Starting LOCAL mode..."
      report "$REPORT_FILE" "$(bold LOCAL)"
      for container_line in "${containers[@]}"; do
        read -r container type <<< "$container_line"
        if [ "$type" != "LOCAL" ]; then
          continue
        fi
        image=$(docker_image "$container")
        info "Using image in local mode: $image..." >&2
        report "$REPORT_FILE" "  $(bold "$image")"

        if $BOOTSTRAP; then
          start=$(date +%s)
          info "Running initial bootstrap..." >&2
          bootstrap "$container"
          end=$(date +%s)
          duration=$((end-start))
          info "Initial bootstrap took $duration seconds for $image." >&2
        fi


        if $TESTS; then
          start=$(date +%s)
          info "Running tests..." >&2
          run_tests "$container"
          end=$(date +%s)
          duration=$((end-start))
          info "Tests took $duration seconds for $image." >&2
        fi

        if $REPEAT; then
          start=$(date +%s)
          info "Running repeat bootstrap to check for idempotency..." >&2
          bootstrap "$container"
          run_tests "$container"
          end=$(date +%s)
          duration=$((end-start))
          info "Repeat bootstrap took $duration seconds for $image." >&2
        fi
      done
    fi

    if $REMOTE; then
      info "Starting REMOTE mode..."
      report "$REPORT_FILE" "$(bold REMOTE)"
      for container_line in "${containers[@]}"; do
        read -r container type <<< "$container_line"
        if [ "$type" != "REMOTE" ]; then
          continue
        fi
        image=$(docker_image "$container")
        info "Using image in local mode: $image..." >&2
        report "$REPORT_FILE" "  $(bold "$image")"

        ip=$(docker_ip "$container")
        debug "Container IP: $ip" >&2

        if $BOOTSTRAP; then
          start=$(date +%s)
          info "Running initial bootstrap..." >&2
          bootstrap_remote "$ip"
          end=$(date +%s)
          duration=$((end-start))
          info "Initial bootstrap took $duration seconds for $image." >&2
        fi


        if $TESTS; then
          start=$(date +%s)
          info "Running tests..." >&2
          run_tests "$container"
          end=$(date +%s)
          duration=$((end-start))
          info "Tests took $duration seconds for $image." >&2
        fi

        if $REPEAT; then
          start=$(date +%s)
          info "Running repeat bootstrap to check for idempotency..." >&2
          bootstrap_remote "$ip"
          run_tests "$container"
          end=$(date +%s)
          duration=$((end-start))
          info "Repeat bootstrap took $duration seconds for $image." >&2
        fi
      done
    fi

    if $TESTS; then
      if [ $RETVAL -eq 0 ]; then
        success "Everithing succeded" >&2
      else
        error "Something failed." >&2
      fi
      info "Test results:\n$(cat $REPORT_FILE)"
    fi

  fi

  if $TEARDOWN; then
    info "Running teardown..." >&2
    teardown
  fi
  exit $RETVAL
}


main
