function previous_release_from {
    local release="${1:-master}"
    local type="${2:-mixed_upgrade}"
    local previous_version=""
    case "${type}" in
        'mixed_upgrade')
            previous_version=$(previous_release_mixed_upgrade_case "${release}");;
        'ffu_upgrade')
            previous_version=$(previous_release_ffu_upgrade_case "${release}");;
        *)
            echo "UNKNOWN_TYPE"
            return 1
            ;;
    esac
    echo "${previous_version}"
}

function previous_release_mixed_upgrade_case {
    local release="${1:-master}"
    case "${release}" in
        ''|master)
            # NOTE: we need to update this when we cut a stable branch
            echo "queens"
            ;;
        queens)
            echo "pike"
            ;;
        pike)
            echo "ocata"
            ;;
        ocata)
            echo "newton"
            ;;
        newton)
            echo "mitaka"
            ;;
        *)
            echo "UNKNOWN_RELEASE"
            return 1
            ;;
    esac
}

function previous_release_ffu_upgrade_case {
    local release="${1:-master}"

    case "${release}" in
        ''|master)
            # NOTE: we need to update this when we cut a stable branch
            echo "newton"
            ;;
        queens)
            echo "newton"
            ;;
        *)
            echo "INVALID_RELEASE_FOR_FFU"
            return 1
            ;;
    esac
}

function is_featureset {
    local type="${1}"
    local featureset_file="${2}"

    [ $(shyaml get-value "${type}" "False"< "${featureset_file}") = "True" ]
}

function run_with_timeout {
    # First parameter is the START_JOB_TIME
    # Second is the command to be executed
    JOB_TIME=$1
    shift
    COMMAND=$@
    # Leave 20 minutes for quickstart logs collection for ovb only
    if [[ "$TOCI_JOBTYPE" =~ "ovb" ]]; then
        RESERVED_LOG_TIME=20
    else
        RESERVED_LOG_TIME=3
    fi
    # Use $REMAINING_TIME of infra to calculate maximum time for remaining part of job
    REMAINING_TIME=${REMAINING_TIME:-180}
    TIME_FOR_COMMAND=$(( REMAINING_TIME - ($(date +%s) - JOB_TIME)/60 - $RESERVED_LOG_TIME))

    if [[ $TIME_FOR_COMMAND -lt 1 ]]; then
        return 143
    fi
    /usr/bin/timeout --preserve-status ${TIME_FOR_COMMAND}m ${COMMAND}
}

function collect_logs {
    cat <<-EOF > $LOGS_DIR/collect_logs.sh
    #!/bin/bash
    set -x

    export NODEPOOL_PROVIDER=${NODEPOOL_PROVIDER:-''}
    export STATS_TESTENV=${STATS_TESTENV:-''}
    export STATS_OOOQ=${STATS_OOOQ:-''}
    export START_JOB_TIME=${START_JOB_TIME:-''}
    export ZUUL_PIPELINE=${ZUUL_PIPELINE:-''}
    export DEVSTACK_GATE_TIMEOUT=${DEVSTACK_GATE_TIMEOUT:-''}
    export REMAINING_TIME=${REMAINING_TIME:-''}
    export LOCAL_WORKING_DIR="$WORKSPACE/.quickstart"
    export OPT_WORKDIR=$LOCAL_WORKING_DIR
    export WORKING_DIR="$HOME"
    export LOGS_DIR=$WORKSPACE/logs
    export VIRTUAL_ENV_DISABLE_PROMPT=1
    export ANSIBLE_CONFIG=$OOOQ_DIR/ansible.cfg
    export ARA_DATABASE=sqlite:///${LOCAL_WORKING_DIR}/ara.sqlite
    export ZUUL_CHANGES=${ZUUL_CHANGES:-''}
    export NODES_FILE=${NODES_FILE:-''}
    export TOCI_JOBTYPE=$TOCI_JOBTYPE
    export STABLE_RELEASE=${STABLE_RELEASE:-''}
    export QUICKSTART_RELEASE=${QUICKSTART_RELEASE:-''}

    set +u
    source $LOCAL_WORKING_DIR/bin/activate
    set -u
    source $OOOQ_DIR/ansible_ssh_env.sh

    /usr/bin/timeout --preserve-status 40m $QUICKSTART_COLLECTLOGS_CMD  > $LOGS_DIR/quickstart_collect_logs.log || \
        echo "WARNING: quickstart collect-logs failed, check quickstart_collectlogs.log for details"

    cp $LOGS_DIR/undercloud/var/log/postci.txt.gz $LOGS_DIR/ || true

    if [[ -e $LOGS_DIR/undercloud/home/$USER/tempest/testrepository.subunit.gz ]]; then
        cp $LOGS_DIR/undercloud/home/$USER/tempest/testrepository.subunit.gz ${LOGS_DIR}/testrepository.subunit.gz
    elif [[ -e $LOGS_DIR/undercloud/home/$USER/pingtest.subunit.gz ]]; then
        cp $LOGS_DIR/undercloud/home/$USER/pingtest.subunit.gz ${LOGS_DIR}/testrepository.subunit.gz
    elif [[ -e $LOGS_DIR/undercloud/home/$USER/undercloud_sanity.subunit.gz ]]; then
        cp $LOGS_DIR/undercloud/home/$USER/undercloud_sanity.subunit.gz ${LOGS_DIR}/testrepository.subunit.gz
    fi

    # Copy tempest.html to root dir
    cp $LOGS_DIR/undercloud/home/$USER/tempest/tempest.html.gz ${LOGS_DIR} || true

    # Copy tempest and .testrepository directory to /opt/stack/new/tempest and
    # unzip
    sudo mkdir -p /opt/stack/new
    sudo cp -Rf $LOGS_DIR/undercloud/home/$USER/tempest /opt/stack/new || true
    sudo gzip -d -r /opt/stack/new/tempest/.testrepository || true

    # record the size of the logs directory
    # -L, --dereference     dereference all symbolic links
    # Note: tail -n +1 is to prevent the error 'Broken Pipe' e.g. 'sort: write failed: standard output: Broken pipe'

    du -L -ch $LOGS_DIR/* | tail -n +1 | sort -rh | head -n 200 &> $LOGS_DIR/log-size.txt || true
EOF

    if [[ "${NODEPOOL_PROVIDER:-''}" == "rdo-cloud-tripleo" ]] || [[ "${NODEPOOL_PROVIDER:-''}" == "tripleo-test-cloud-rh1" ]]; then
        if [[ "$TOCI_JOBTYPE" =~ "ovb" ]]; then
            bash $LOGS_DIR/collect_logs.sh
            # rename script to not to run it in multinode jobs
            mv $LOGS_DIR/collect_logs.sh $LOGS_DIR/ovb_collect_logs.sh
        fi
    fi

}
