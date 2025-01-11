#!/bin/bash

AGENT_X64_URL=https://pcdn.titannet.io/test4/bin/agent-linux.zip
AGENT_ARM_URL=https://pcdn.titannet.io/test4/bin/agent-arm.zip

WORKSPACE=/app/data/agent
AGENT_PATH=/app/agent
MULTIPASS_PATH=/app/multipass
SERVER_URL=${SERVER_URL:-https://test4-api.titannet.io}
DATA_DIR=/app/data
MULTIPASS_SOCKET_PATH=/run/multipass_socket


install_agent() {
    case "$TARGETARCH" in \
        amd64)  AGENT_URL=$AGENT_X64_URL ;; \
        arm64)  AGENT_URL=$AGENT_ARM_URL ;; \
        
        *)     echo "Unsupported architecture: $TARGETARCH"; exit 1 ;; \
    esac
   
    mkdir -p $AGENT_PATH
    cd $AGENT_PATH

    echo "Downloading agent from $AGENT_URL"
    curl -L $AGENT_URL -o agent.zip
    unzip agent.zip
    chmod +x agent
    rm agent.zip
    echo "Agent installed"
}

run_agent() {
    echo "Start agent"
    cd $AGENT_PATH

    mkdir -p $WORKSPACE

    export LOG_FILE=$WORKSPACE/agent.log

    $AGENT_PATH/agent --working-dir=$WORKSPACE --server-url=$SERVER_URL --key=$KEY &
    agentId=$!
}

run_multipass() {
    echo "Starting multipass..."

    cd $MULTIPASS_PATH
    mkdir -p $DATA_DIR/multipass
    # 如果 ~/.config 軟連結 存在，則刪除並建立連結
    if [[ -L ~/.config ]]; then
        rm ~/.config
    fi

    mkdir -p $DATA_DIR/.config
    ln -s $DATA_DIR/.config ~/.config

    export MULTIPASS_STORAGE=$DATA_DIR/multipass

    ./multipassd &
    multipassId=$!
    export MULTIPASS_SERVER_ADDRESS=unix:$MULTIPASS_SOCKET_PATH

    sleep 20

    echo "Waiting for multipass socket to be ready..."
    for i in {1..60}; do
        if [[ -S $MULTIPASS_SOCKET_PATH ]]; then
            echo "Multipass socket is ready."
            break
        fi
        sleep 1
    done

    if [[ ! -S $MULTIPASS_SOCKET_PATH ]]; then
        echo "Multipass socket is still not available after 60 seconds."
        kill $multipassId
        return 1
    fi

    # 如果密碼未設定(~/.config/multipassd/multipassd.conf 包含 local.passphrase=)，則設定密碼
    if ! grep -q "local.passphrase=" ~/.config/multipassd/multipassd.conf; then
        /app/set_passphrase.sh
        sleep 5
        if ! kill -0 $multipassId 2>/dev/null; then
            export MULTIPASS_STORAGE=$DATA_DIR/multipass
            ./multipassd &
            multipassId=$!
            export MULTIPASS_SERVER_ADDRESS=unix:$MULTIPASS_SOCKET_PATH
        fi
        sleep 20
    else
        echo "Multipass passphrase is already set."
    fi

    multipass authenticate $MULTIPASS_PASSPHRASE

    if multipass list; then
        echo "Multipass client connected successfully."
        # # set driver to qemu
        # multipass set local.driver=qemu

        # sleep 5
        # if ! kill -0 $multipassId 2>/dev/null; then
        #     export MULTIPASS_STORAGE=$DATA_DIR/multipass
        #     ./multipassd &
        #     multipassId=$!
        #     export MULTIPASS_SERVER_ADDRESS=unix:$MULTIPASS_SOCKET_PATH
        # fi
        # sleep 20
    else
        echo "Multipass client failed to connect."
        kill $multipassId
        return 1
    fi
    echo "Multipass started with pid $multipassId"
}

main() {
    if [ -z "$KEY" ]; then
        echo "Error: --key is required"
        exit 1
    fi
    
    install_agent

    run_multipass

    run_agent

    while true; do
        sleep 1
        # check if agent is still running
        if ! kill -0 $agentId 2>/dev/null; then
            echo "Agent stopped restarting..."
            run_agent
        fi

        # check if multipass is still running
        if ! kill -0 $multipassId 2>/dev/null; then
            echo "Multipass stopped restarting..."
            cd $MULTIPASS_PATH
            ./multipassd &
            multipassId=$!
            sleep 20
        fi
    done
}

main "$@"