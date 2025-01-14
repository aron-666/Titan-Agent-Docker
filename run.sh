#!/bin/bash

AGENT_X64_URL=https://pcdn.titannet.io/test4/bin/agent-linux.zip
AGENT_ARM_URL=https://pcdn.titannet.io/test4/bin/agent-arm.zip

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

    $AGENT_PATH/agent --working-dir=$WORKSPACE --server-url=$SERVER_URL --key=$KEY &
    agentId=$!
}

start_multipass() {
    cd $MULTIPASS_PATH
    sleep 5

    ./multipassd &
    multipassId=$!
    sleep 15

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

    start_multipass
    # check return code
    if [ $? -ne 0 ]; then
        return 1
    fi

    # 如果密碼未設定(~/.config/multipassd/multipassd.conf 包含 local.passphrase=)，則設定密碼
    if ! grep -q "local.passphrase=" ~/.config/multipassd/multipassd.conf; then
        /app/set_passphrase.sh
        sleep 10
        if ! kill -0 $multipassId 2>/dev/null; then
            start_multipass
        fi
    else
        echo "Multipass passphrase is already set."
    fi

    multipass authenticate $MULTIPASS_PASSPHRASE

    # check ~/.config/multipassd/multipassd.conf 是否有 local.driver=qemu
    if ! grep -q "local.driver=qemu" ~/.config/multipassd/multipassd.conf; then
        echo "Setting multipass driver to qemu."
        multipass set local.driver=qemu
        sleep 15
        if ! kill -0 $multipassId 2>/dev/null; then
            kill $multipassId
            start_multipass
            multipass authenticate $MULTIPASS_PASSPHRASE
        fi
    else
        echo "Multipass driver is already set to qemu."
    fi

    

    if multipass list; then
        echo "Multipass client connected successfully."
    else
        echo "Multipass client failed to connect."
        kill $multipassId
        start_multipass
        multipass authenticate $MULTIPASS_PASSPHRASE

        if multipass list; then
            echo "Multipass client connected successfully."
        else
            echo "Multipass client failed to connect."
            kill $multipassId

            return 1
        fi

    fi
    echo "Multipass started with pid $multipassId"
}

main() {
    if [ -z "$KEY" ]; then
        echo "Error: --key is required"
        exit 1
    fi

    # 禁用 IPv6
    sysctl -w net.ipv6.conf.all.disable_ipv6=1
    sysctl -w net.ipv6.conf.default.disable_ipv6=1
    
    install_agent

    run_multipass
    # check return code
    if [ $? -ne 0 ]; then
        echo "Failed to start multipass."
        exit 1
    fi

    run_agent

    while true; do
        sleep 10
        # check if agent is still running
        if ! kill -0 $agentId 2>/dev/null; then
            echo "Agent stopped restarting......."
            run_agent
        fi

        # check if multipass is still running
        if ! kill -0 $multipassId 2>/dev/null; then
            echo "Multipass stopped restarting......."
            kill $multipassId
            start_multipass
            multipass authenticate $MULTIPASS_PASSPHRASE
        fi


        if ! multipass list > /dev/null 2>&1; then
            echo "Multipass client failed to connect."
            
            if [ -n "$multipassId" ]; then
                kill $multipassId
            fi
            
            sleep 15
            start_multipass
            sleep 6
            
            if multipass authenticate $MULTIPASS_PASSPHRASE; then
                if multipass list > /dev/null 2>&1; then
                    echo "Multipass client connected successfully."
                    echo "Multipass started with pid $multipassId"
                else
                    echo "Multipass client failed to connect."
                    if [ -n "$multipassId" ]; then
                        kill $multipassId
                    fi
                fi
            else
                echo "Multipass authentication failed."
            fi
        fi

        # 偵測 multipass list 是否包含 ubuntu-niulink 並且狀態不為 Running ，則啟動
        # if multipass list | grep -q "ubuntu-niulink"; then
        #     if ! multipass list | grep -q "ubuntu-niulink.*Running"; then
        #         sleep 10
        #         if ! multipass list | grep -q "ubuntu-niulink.*Running"; then
        #             echo "Starting ubuntu-niulink..."
        #             multipass start ubuntu-niulink
        #         fi
                
        #     fi
        # fi
        
    done
}

main "$@"