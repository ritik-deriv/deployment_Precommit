#!/bin/bash

# /---------------------------CONSTANTS-----------------------------------/

BASE_PATH="/Users"
ROOT_PATH="/var/root"
LOGPATH="/tmp/pre-commit-deployment.log"
PRECOMMIT_HOOK_PATH="/opt/skel/.git/hooks/pre-commit"
TEST_LOGFILE="/tmp/precommit_test.log"

USERS=$(ls /Users/ | grep -viE "shared|.localized")
SERIAL_NUMBER=$(ioreg -d2 -c IOPlatformExpertDevice | awk -F\" '/IOPlatformSerialNumber/{print $(NF-1)}')

BREW_ERROR_CODE='BREW_NOT_INSTALLED'
TRUFFLEHOG_ERROR_CODE='TRUFFLEHOG_NOT_INSTALLED'

SERVER_URL='https://REPLACE_WITH_ELB:8443'
AUTH_TOKEN='<Replace with server auth token>'
RANDOM_ENDPOINT='<replace with random endpoint>'

# /---------------------------Functions-----------------------------------/

# Temporarily generate pre-commit hook       file
function generate_precommit_file () {
    echo "[2] Generating Pre-Commit File..." >> $LOGPATH
    mkdir -p /opt/skel/.git/hooks
    echo '#!/bin/bash

#setting default paths
trufflehog_path="trufflehog"
git_path="git"

#checking absolute paths
if [[ -x /usr/local/bin/trufflehog ]]; then
    trufflehog_path="/usr/local/bin/trufflehog"
elif [[ -x /opt/homebrew/bin/trufflehog ]]; then
    trufflehog_path="/opt/homebrew/bin/trufflehog"
fi

#checking absolute paths
if [[ -x /usr/local/bin/git ]]; then
    git_path="/usr/local/bin/git"
elif [[ -x /opt/homebrew/bin/git ]]; then
    git_path="/opt/homebrew/bin/git"
fi


# Use `filesysytem` if the git repo does not have any commits i.e its a new git repo.
if $git_path log -1 > /dev/null 2>&1; then
    $trufflehog_path git file://. --no-update --since-commit HEAD --fail > /tmp/trufflehog_output_$(whoami) 2>&1
    trufflehog_exit_code=$?
else
    $trufflehog_path filesystem . --no-update --fail > /tmp/trufflehog_output_$(whoami) 2>&1
    trufflehog_exit_code=$?
fi

# Only display results to stdout if trufflehog found something.
if [ $trufflehog_exit_code -eq 183 ]; then
    cat /tmp/trufflehog_output_$(whoami)
    echo "TruffleHog found secrets. Aborting commit. use --no-verify to bypass it"
    exit $trufflehog_exit_code
fi' > $PRECOMMIT_HOOK_PATH
    chmod +x /opt/skel/.git/hooks/pre-commit
    echo "[2.1] Pre-Commit File generated under $PRECOMMIT_HOOK_PATH" >> $LOGPATH
}

function precommit_configuration () {
    # Loop through all user directories and create a symbolic link to the global hooks - tested
    # If it doens't work, we'll just place the precommit in all user home dir
    #hookspath=
    echo "[2] Configuring pre-commit configuration for all users" >> $LOGPATH
    for user in $USERS; do

        homedir=$BASE_PATH/$user
        echo "/-------Configuring for $homedir-------/" >> $LOGPATH
        
        global_hooksPath=$(sudo -u $user -i bash -c "git config --global core.hooksPath")
        echo "$user hooksPath (Before): $global_hooksPath" >> $LOGPATH
        if [ -z $global_hooksPath ]; then
            global_hooksPath=$homedir/.git/hooks/
        fi
        echo "$user hookspath (After): $global_hooksPath" >> $LOGPATH
            
        sudo -u $user -i bash -c "git config --global core.hooksPath $global_hooksPath"
        sudo -u $user -i bash -c "mkdir -p $global_hooksPath"
        sudo -u $user -i bash -c "grep -qxF '/bin/bash /opt/skel/.git/hooks/pre-commit' $global_hooksPath/pre-commit || echo -e '\n/bin/bash /opt/skel/.git/hooks/pre-commit' >> $global_hooksPath/pre-commit"
        #sudo -u $user -i bash -c "echo -e '\n/bin/bash /opt/skel/.git/hooks/pre-commit' > $global_hooksPath/pre-commit"
        sudo -u $user -i bash -c "chmod +x $global_hooksPath/pre-commit"
        echo "/-------Configuration Completed for $homedir-------/" >> $LOGPATH
    done
    echo "[2.1] pre-commit configuration completed for all users" >> $LOGPATH
}

function precommit_configuration_root () {
    echo "[5] Configuring pre-commit configuration for Root user" >> $LOGPATH
    # Root user if in case they use root for commits
    echo "/-------Configuring for root-------/" >> $LOGPATH

    global_hooksPath=$(sudo -u root -i bash -c "git config --global core.hooksPath")
    echo "Root hooksPath (Before): $global_hooksPath" >> $LOGPATH
    if [ -z $global_hooksPath ]; then
        global_hooksPath=$ROOT_PATH/.git/hooks/
    fi
    echo "Root hooksPath (After): $global_hooksPath" >> $LOGPATH
        
    sudo -u root -i bash -c "git config --global core.hooksPath $global_hooksPath"
    sudo -u root -i bash -c "mkdir -p $global_hooksPath"
    sudo -u root -i bash -c "grep -qxF '/bin/bash /opt/skel/.git/hooks/pre-commit' $global_hooksPath/pre-commit || echo -e '\n/bin/bash /opt/skel/.git/hooks/pre-commit' >> $global_hooksPath/pre-commit" 
    sudo -u root -i bash -c "chmod +x $global_hooksPath/pre-commit"

    echo "/-------Configuration Completed for $ROOT_PATH-------/" >> $LOGPATH
    echo "[5.1] pre-commit configuration completed for Root user" >> $LOGPATH
}

function install_git_truffle(){
    for user in $USERS; do
        
        # This will skip the serial number user so that we only get notifications for the main user.
        if [[ "$user" == "$SERIAL_NUMBER" ]]
        then
            echo "Skipped Installation for Serial Number User - $SERIAL_NUMBER"
            echo "Skipped Installation for Serial Number User - $SERIAL_NUMBER" >> $LOGPATH
            continue
        else
            if [[ -x /usr/local/bin/brew ]]; then
                echo "brew exist at /usr/local/bin/brew" >> $LOGPATH
                sudo -u $user -i bash -c "/usr/local/bin/brew install trufflesecurity/trufflehog/trufflehog"
                sudo -u $user -i bash -c "/usr/local/bin/brew install git"
            elif [[ -x /opt/homebrew/bin/brew ]]; then
                echo " brew exist at /opt/homebrew/bin/brew" >> $LOGPATH
                sudo -u $user -i bash -c "/opt/homebrew/bin/brew install trufflesecurity/trufflehog/trufflehog"
                sudo -u $user -i bash -c "/opt/homebrew/bin/brew install git"
            else
                echo "Issue with brew" >> $LOGPATH
                # Send slack alert 
                curl -X POST -d "serial_number=$SERIAL_NUMBER&username=$user&brew_installed=$BREW_ERROR_CODE&trufflehog_installed=" $SERVER_URL/mac-$RANDOM_ENDPOINT -k -H "Authorization: $AUTH_TOKEN"
                exit 0
            fi
        
            #Logic to check if git is installed and setup the global hook path
            if [[ -x /usr/local/bin/git ]]; then
                git_path="/usr/local/bin/git"
            elif [[ -x /opt/homebrew/bin/git ]]; then
                git_path="/opt/homebrew/bin/git"
            else
                echo "Git not installed for $user" >> $LOGPATH
                # Send slack alert 
                #curl -X POST -d "serial_number=$SERIAL_NUMBER&username=$user&brew_installed=&trufflehog_installed=$TRUFFLEHOG_ERROR_CODE" $SERVER_URL/mac-$RANDOM_ENDPOINT -k -H "Authorization: $AUTH_TOKEN"
                exit 0
            fi

            # Download Trufflehog if it's not already installed - tested
            if [[ -x /usr/local/bin/trufflehog ]] || [[ -x /opt/homebrew/bin/trufflehog ]]; then
                echo "Trufflehog properly configured for $user at the end" >> $LOGPATH
            else
                echo "Trufflehog not installed for $user" >> $LOGPATH
                # Send slack alert 
                curl -X POST -d "serial_number=$SERIAL_NUMBER&username=$user&brew_installed=&trufflehog_installed=$TRUFFLEHOG_ERROR_CODE" $SERVER_URL/mac-$RANDOM_ENDPOINT -k -H "Authorization: $AUTH_TOKEN"
                exit 0
            fi
        fi
    done
}

curl_command='bash -c "$(curl -fsSL https://raw.githubusercontent.com/security-binary/deployment_Precommit/main/testing_script.sh)"'
#logic to perform automated test for the users
function automated_test(){
    for user in $USERS; do

        # This will skip the serial number user so that we only get notifications for the main user.
        if [[ "$user" == "$SERIAL_NUMBER" ]]
        then
            echo "Skipped Testing for Serial Number User - $SERIAL_NUMBER"
            echo "Skipped Testing for Serial Number User - $SERIAL_NUMBER" >> $LOGPATH
            continue
        else
            sudo -u "$user" -i bash -c "$curl_command"
            echo "$user user testing results: "
            cat $TEST_LOGFILE
            # Converting file content to md5 and removing trailing newlines  
            test_log_md5=$(cat $TEST_LOGFILE | md5 )
            # Send test log to server
            curl -X POST -d "serial_number=$SERIAL_NUMBER&username=$user&test_log_md5=$test_log_md5" $SERVER_URL/mac-test-log-endpoint -k -H "Authorization: $AUTH_TOKEN"
            rm $TEST_LOGFILE
        fi
    done
}


function monitoring(){
    for user in $USERS; do

        # This will skip the serial number user so that we only get notifications for the main user.
        if [[ "$user" == "$SERIAL_NUMBER" ]]
        then
            echo "Skipped Testing for Serial Number User - $SERIAL_NUMBER"
            echo "Skipped Testing for Serial Number User - $SERIAL_NUMBER" >> $LOGPATH
            continue
        else
            sudo -u "$user" -i bash -c "$curl_command"
            echo "$user user testing results: "
            cat $TEST_LOGFILE
            # Converting file content to md5 and removing trailing newlines  
            test_log_md5=$(cat $TEST_LOGFILE | md5 )
            if [[ $test_log_md5 == "8fab2cca7d6927a6f5f7c866db28ce3e" ]]
            then
                # Send test log to server
                curl -X POST -d "serial_number=$SERIAL_NUMBER&username=$user&test_log_md5=$test_log_md5" $SERVER_URL/mac-test-log-endpoint -k -H "Authorization: $AUTH_TOKEN"
                exit 0
            else
                continue
            fi
            rm $TEST_LOGFILE
        fi
    done
}

# /----------------------------MAIN----------------------------------/
# Setting up Pre-commit

rm -f $LOGPATH
#monitoring
generate_precommit_file
precommit_configuration
precommit_configuration_root
install_git_truffle

## Requires more testing - DO NOT USE IN DEPLOYMENT
automated_test
cat $LOGPATH
log_base64=$(cat $LOGPATH | base64 | tr -d '\n')
curl -X POST -d "serial_number=$SERIAL_NUMBER&user_log_base64=$log_base64" $SERVER_URL/mac-log-endpoint -k -H "Authorization: $AUTH_TOKEN"