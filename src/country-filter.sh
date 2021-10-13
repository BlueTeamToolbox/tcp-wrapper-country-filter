#!/usr/bin/env bash
# ---------------------------------------------------------------------------------------- #
# Description                                                                              #
# ---------------------------------------------------------------------------------------- #
# Implement country level blocking via TCP Wrappers. Requires geoiplookup to identify the  #
# country for a given IP address and then applies the default 'ACTION'.                    #
#                                                                                          #
# Action:                                                                                  #
#     ALLOW: Allow connections ONLY from the specified countries.                          #
#     DENY: Deny all connections from specified countries.                                 #
# ---------------------------------------------------------------------------------------- #
# TCP Wrapper config:                                                                      #
#                                                                                          #
# /etc/hosts.allow                                                                         #
#      sshd: ALL: aclexec /usr/sbin/county-filter %a                                       #
#                                                                                          #
# /etc/hosts.deny                                                                          #
#      sshd: ALL                                                                           #
# ---------------------------------------------------------------------------------------- #

ALLOW_ACTION='ALLOW'
DENY_ACTION='DENY'

# space-separated list of country codes
COUNTRIES=''

# The action to take when a country is matched
ACTION=$DENY_ACTION

# ---------------------------------------------------------------------------------------- #
# In multiplexer                                                                           #
# ---------------------------------------------------------------------------------------- #
# A simple wrapper to check if the script is being run via the multiplex or not.           #
# ---------------------------------------------------------------------------------------- #

function in_multiplexer
{
    [[ "${MUX}" = true ]] && return 0 || return 1;
}

# ---------------------------------------------------------------------------------------- #
# In terminal                                                                              #
# ---------------------------------------------------------------------------------------- #
# A wrapper to check if the script is being run in a terminal or not.                      #
# ---------------------------------------------------------------------------------------- #

function in_terminal
{
    [[ -t 1 ]] && return 0 || return 1;
}

# ---------------------------------------------------------------------------------------- #
# Debug                                                                                    #
# ---------------------------------------------------------------------------------------- #
# Show output only if we are running in a terminal, but always log the message.            #
# ---------------------------------------------------------------------------------------- #

function debug()
{
    local message="${1:-}"

    if [[ -n "${message}" ]]; then
        if in_terminal || in_multiplexer; then
            echo "${message}"
        fi
        logger "${message}"
    fi
}

# ---------------------------------------------------------------------------------------- #
# Check results                                                                            #
# ---------------------------------------------------------------------------------------- #
# Check individual results against a given array and deny where applicable.                #
# ---------------------------------------------------------------------------------------- #

function check_results()
{
    local item="${1:-}"
    local list="${2:-}"

    #
    # Check the current item and list and decide what action to take
    #
    if [[ "${ACTION}" == "${DENY_ACTION}" ]]; then
        [[ $list =~ $item ]] && RESPONSE=${DENY_ACTION} || RESPONSE=${ALLOW_ACTION}
    else
        [[ $list =~ $item ]] && RESPONSE=${ALLOW_ACTION} || RESPONSE=${DENY_ACTION}
    fi

    if [[ $RESPONSE = "${DENY_ACTION}" ]]; then
        debug "$RESPONSE sshd connection from ${IP} ($item)"
        exit 1
    fi

    #
    # Default (REPONSE=ALLOW) is to do nothing
    #
}

# ---------------------------------------------------------------------------------------- #
# Handle country blocks                                                                    #
# ---------------------------------------------------------------------------------------- #
# Lookup the country for a given IP, it should only have, at most, one entry, capture the  #
# country code and test each it to ensure it is not bocked.                                #
# ---------------------------------------------------------------------------------------- #

function handle_country_blocks
{
    #
    # Local variables
    #
    local GEOLOOKUP
    local VERSION
    local v6_regex='^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$'

    #
    # Workout if the IP is a V6 address or not
    #
    if [[ ${IP} =~ $v6_regex ]]; then
        GEOLOOKUP=$(command -v geoiplookup6)
        VERSION=6
    else
        GEOLOOKUP=$(command -v geoiplookup)
    fi

    #
    # Do the lookup and let check_results handle the blocking
    #
    if [[ -z "${GEOLOOKUP}" ]]; then
        debug "geoiplookup${VERSION} is not installed - Skipping"
    else
        COUNTRY=$("${GEOLOOKUP}" "${IP}" | awk -F ": " '{ print $2 }' | awk -F "," '{ print $1 }' | head -n 1)

        #
        # If we cannot find the country then set a default value we can match on
        #
        if [[ "${COUNTRY}" == 'IP Address not found' ]]; then
            COUNTRY='XX'
        fi

        check_results "${COUNTRY}" "${COUNTRIES}"
    fi
}

# ---------------------------------------------------------------------------------------- #
# Main()                                                                                   #
# ---------------------------------------------------------------------------------------- #
# The main function where all of the heavy lifting and script config is done.              #
# ---------------------------------------------------------------------------------------- #

function main()
{
    #
    # NO IP given - error and abort
    #
    if [[ -z "${1}" ]]; then
        debug 'Ip addressed not supplied - Aborting'
        exit 0
    fi

    #
    # Set a variable (Could pass it at function call)
    #
    declare -g IP="${1}"

    #
    # Are we being called from the multiplexer?
    #
    if [[ -n "${2}" ]]; then
        declare -g MUX=true
    else
        declare -g MUX=false
    fi

    #
    # Turn off case sensitivity
    #
    shopt -s nocasematch

    #
    # Country level blocking
    #
    handle_country_blocks

    # Default allow
    exit 0
}

# ---------------------------------------------------------------------------------------- #
# Main()                                                                                   #
# ---------------------------------------------------------------------------------------- #
# The actual 'script' and the functions/sub routines are called in order.                  #
# ---------------------------------------------------------------------------------------- #

main "${@}"

# ---------------------------------------------------------------------------------------- #
# End of Script                                                                            #
# ---------------------------------------------------------------------------------------- #
# This is the end - nothing more to see here.                                              #
# ---------------------------------------------------------------------------------------- #
