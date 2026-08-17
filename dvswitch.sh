#!/bin/bash

#################################################################
# /*
#  * Copyright (C) 2019, 2020, 2021 N4IRR
#  *
#  * Permission to use, copy, modify, and/or distribute this software for any
#  * purpose with or without fee is hereby granted, provided that the above
#  * copyright notice and this permission notice appear in all copies.
#  *
#  * THE SOFTWARE IS PROVIDED "AS IS" AND ISC DISCLAIMS ALL WARRANTIES WITH
#  * REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
#  * AND FITNESS.  IN NO EVENT SHALL N4IRR BE LIABLE FOR ANY SPECIAL, DIRECT,
#  * INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
#  * LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE
#  * OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
#  * PERFORMANCE OF THIS SOFTWARE.
#  * 
#  * Fixes and updates by KE2HNI
#  */
#################################################################

#DEBUG=echo
#set -xv   # this line will enable debug


SCRIPT_VERSION="1.6.4"

AB_DIR=${AB_DIR:-"/var/lib/dvswitch"}
MMDVM_DIR=${MMDVM_DIR:-"/var/lib/mmdvm"}
DVSWITCH_INI=${DVSWITCH_INI:-"/opt/MMDVM_Bridge/DVSwitch.ini"}
MMDVM_INI=${MMDVM_INI:-"/opt/MMDVM_Bridge/MMDVM_Bridge.ini"}
NODE_DIR=${NODE_DIR:-"/tmp"}

# Default server and port assignment, but overridden by value in ABInfo
TLV_PORT=36000
USRP_PORT=32001
SERVER=127.0.0.1

# HTTP_PORT is used for the simple server that supports data file uploads
HTTP_PORT=9042

# Error codes defined below
SUCCESSS=0
ERROR_FILE_NOT_FOUND=-1
ERROR_INVALID_ARGUMENT=-2
ERROR_EMPTY_FILE=-3
ERROR_DIR_NOT_FOUND=-4
ERROR_INVALID_FILE=-5
ERROR_LOOKUP_FAILED=-6
ERROR_INI_FAILURE=-7
_ERRORCODE=$SUCCESSS

#################################################################
# Return value from ABInfo_xxxx.json
# The value may be an value, object/value or object/object/value
#################################################################
function getABInfoValue() {
    declare _json_file=`getABInfoFileName`
python3 - <<END
#!/usr/bin/env python
try:
    import json, os, sys

    json = json.loads(open("$_json_file").read())
    if "$2" == "":  # Not all values are enclosed in an object
        value = json["$1"]
    else:
        if "$3" == "":
            value = json["$1"]["$2"]
        else:
            value = json["$1"]["$2"]["$3"]
    print(value)
except:
    sys.stderr.write("getABInfoValue: error getting value(s) $1 $2 $3\n")
    print("ERROR")
    exit(1)
END
}

#################################################################
# get file name of the current ABInfo json file
#################################################################
function getABInfoFileName() {
        if [ -z "${ABINFO}" ]; then # if no enviornment variable, use the latest file in /tmp
        declare _json_file=`ls -t /tmp/ABInfo_*.json 2>/dev/null | head -1`
    else
        declare _json_file=$ABINFO  # Use the environment variable (probably set by AB)
    fi
    echo $_json_file
}

#################################################################
# Parse and print out an ini file value
# parseIniFile fileName stanza tag
#################################################################
function parseIniFile() {
python3 - <<END
#!/usr/bin/env python
try:
    import sys, configparser
    with open("$1") as f:
        file_content = '[dummy_section]\n' + f.read()
    config = configparser.RawConfigParser(inline_comment_prefixes=(';',))
    config.read_string(file_content)
    print( config.get('$2', '$3') )
except:
    sys.stderr.write("parseIniFile: Config parse error for file: $1.  Error: " + str(sys.exc_info()[1]) + "\n")
    print("ERROR")
    exit(1)
END
}

#################################################################
# Return TLV_PORT from ABInfo_xxxx.json
# This is the port  that AB is listening to for commands and MB 
# packets.
#################################################################
function getTLVPort() {
    getABInfoValue tlv rx_port
}

#################################################################
# Return USRP_PORT from ABInfo_xxxx.json
# This is the port  that AB is listening to for commands and MB 
# packets.
#################################################################
function getUSRPPort() {
    getABInfoValue usrp rx_port
}

#################################################################
# Tune to a specific TG/Reflector/Server, etc
# Argument 1 is the TG to tune to.  The argument is mode specific.
#################################################################
function tune() {
    if [ $# -eq 0 ]; then
        getABInfoValue last_tune
    else
        remoteControlCommand "txTg=$1"
    fi
}

#################################################################
# Set the number of bits that AB will use to encode a PCM sample
# The bits in argument 1 (48, 49, 72 or 88) are mode specific
#################################################################
function setAmbeSize() {
    if [ $# -eq 0 ]; then
        getABInfoValue tlv ambe_size
    else
        remoteControlCommand "ambeSize=$1"
    fi
}

#################################################################
# Set the slot to transmit on.  Slot may be 1 or 2
#################################################################
function setSlot() {
    if [ $# -eq 0 ]; then
        getABInfoValue digital ts
    else
        remoteControlCommand "txTs=$1"
    fi
}

#################################################################
# Set the AMBE mode of Analog_Bridge to DMR|DSTAR|NXDN|YSFN|YSFW|P25
#################################################################
function setAmbeMode() {
    if [ $# -eq 0 ]; then
        getABInfoValue tlv ambe_mode
    else
        remoteControlCommand "ambeMode=$1"
    fi
}

#################################################################
# Send graceful exit command to Analog_Bridge
#################################################################
function exitAnalogBridge() {
    remoteControlCommand "exit=$1 $2"
}

#################################################################
# Set the analog audio shaping type
# argument may be AUDIO_UNITY, AUDIO_USE_AGC, AUDIO_USE_GAIN
#################################################################
function setUSRPAudioType() {
    if [ $# -eq 0 ]; then
        getABInfoValue usrp to_pcm shape
    else
        remoteControlCommand "usrpAudio=$1"
    fi
}

#################################################################
# Set the digital audio shaping type
# argument may be AUDIO_UNITY, AUDIO_USE_GAIN, AUDIO_USE_BPF
#################################################################
function setTLVAudioType() {
    if [ $# -eq 0 ]; then
        getABInfoValue usrp to_ambe shape
    else
        remoteControlCommand "tlvAudio=$1"
    fi
}

#################################################################
# Set the analog (PCM) audio gain
#  Argument may be between 0 - x, where
# < 1 will decrease audio level from unity
# 1 = UNITY gain
# > 1 will increase audio level above unity
#################################################################
function setUSRPGain() {
    if [ $# -eq 0 ]; then
        getABInfoValue usrp to_pcm gain
    else
        remoteControlCommand "usrpGain=$1"
    fi
}

#################################################################
# Set the digital audio gain
#################################################################
function setTLVGain() {
    if [ $# -eq 0 ]; then
        getABInfoValue usrp to_ambe gain
    else
        remoteControlCommand "tlvGain=$1"
    fi
}

#################################################################
# Set the USRP agc params to threshold, slope and decay
#################################################################
function setUSRPAgc() {
    if [ $# -eq 0 ]; then
        echo "Argument required: AGC parameters (threshold, slope  and decay)"
        _ERRORCODE=$ERROR_INVALID_ARGUMENT
    else
        remoteControlCommand "agcUSRP=$1,$2,$3"
    fi
}

#################################################################
# Set the TLV agc params to threshold, slope and decay
#################################################################
function setTLVAgc() {
    if [ $# -eq 0 ]; then
        echo "Argument required: AGC parameters (threshold, slope  and decay)"
        _ERRORCODE=$ERROR_INVALID_ARGUMENT
    else
        remoteControlCommand "agcTLV=$1,$2,$3"
    fi
}

#################################################################
# Set the USRP audio codec to {SLIN|ULAW|ADPCM}
#################################################################
function setUSRPCodec() {
    if [ $# -eq 0 ]; then
        echo "Argument required: codec"
        _ERRORCODE=$ERROR_INVALID_ARGUMENT
    else
        string='|SLIN|ULAW|ADPCM|slin|ulaw|adpcm|'
        if [[ $string == *"|$1|"* ]]; then
            remoteControlCommand "codec=$1"
        else
            echo "Invalid argument: {slin|ulaw|adpcm}"
            _ERRORCODE=$ERROR_INVALID_ARGUMENT
        fi
    fi
}

#################################################################
# set the AB listener port
#################################################################
function setTLVRxPort() {
    if [ $# -eq 0 ]; then
        getABInfoValue tlv rx_port
    else
        remoteControlCommand "rxport=$1"
        sleep 1
        TLV_PORT=`getTLVPort`   # We have changed the listener on AB, so we must adjust our sending port
    fi
}

#################################################################
# Set the AB -> MB transmit port
#################################################################
function setTLVTxPort() {
    if [ $# -eq 0 ]; then
        getABInfoValue tlv tx_port
    else
        remoteControlCommand "txport=$1"
    fi
}

#################################################################
# Send the info packet to a USRP client (DVSM/UC)
#################################################################
function getInfo() {
    if [ $# -eq 0 ]; then
        remoteControlCommand "info"
    else
        getABInfoValue $1 $2
    fi
}

#################################################################
# mute AB ("OFF", "USRP", "TLV", "BOTH")
#################################################################
function setMute() {
    if [ $# -eq 0 ]; then
        getABInfoValue mute
    else
        remoteControlCommand "mute=$1"
    fi
}

#################################################################
# Send "text" message to Mobile
#################################################################
function sendMessage() {
    if [ -z "$1" ]; then
        echo "Argument required: text"
        _ERRORCODE=$ERROR_INVALID_ARGUMENT
    else
        remoteControlCommand "message=$1"
    fi
}

#################################################################
# Send a macro definition or file to Mobile
#################################################################
function sendMacro() {
    if [ -z "$2" ]; then
        echo "Argument required: file or text"
        _ERRORCODE=$ERROR_INVALID_ARGUMENT
    else
        remoteControlCommand "$1=$2"
    fi
}

#################################################################
# Set the ping timer (keep alive)
#################################################################
function setPingTimer() {
    if [ -z "$1" ]; then
        getABInfoValue usrp ping
    else
        remoteControlCommand "ping=$1"
    fi
}

#################################################################
# Tell AB to reload database files from disk into memory
#################################################################
function reloadDatabase() {
    remoteControlCommand "reloadDatabase"
}

#################################################################
# Send the remote control TLV command to Analog_Bridge
#################################################################
function remoteControlCommand() {
    if [ ! -z "${DEBUG}" ]; then
        echo "remoteControlCommand $1"
    else
PYTHON_ARG="$1" python3 - <<END
#!/usr/bin/env python
try:
    import sys, socket, struct, os
    cmd = os.environ['PYTHON_ARG'].replace("\\\" + "n", "\n").encode("utf-8")
    _sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    cmd = struct.pack("BB", 0x05, len(cmd))[0:2] + cmd
    _sock.sendto(cmd, ('$SERVER', $TLV_PORT))
    _sock.close()
except:
    print('$SERVER', '$TLV_PORT')
    sys.stderr.write("remoteControlCommand: error sending command " + str(sys.exc_info()[1]) + "\n")
    exit(1)
END
    fi
}

#################################################################
# Compose a USRP packet and send it to AB (WIP: address and port)
#################################################################
function USRPCommand() {
python3 - <<END
#!/usr/bin/env python
import traceback, struct, socket, sys
try:
    usrpSeq = 1
    packetType = $1
    cmd = "$2"
    usrp = 'USRP'.encode('ASCII') + (struct.pack('>iiiiiii',usrpSeq, 0, 0, 0, packetType << 24, 0, 0)) + cmd.encode("utf-8") + struct.pack('>i',0)
    usrpSeq = (usrpSeq + 1) & 0xffff
    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp.sendto(usrp, ('$SERVER', $USRP_PORT))
    udp.close()
except:
    sys.stderr.write("USRPCommand: error sending command\n")
    traceback.print_exc()
END
}

#################################################################
# 
#################################################################
function setCallAndID() {
    if [ ! -z "${DEBUG}" ]; then
        echo "setCallAndID $1"
    else
python3 - <<END
#!/usr/bin/env python
try:
    import sys, socket, struct

    call = "$1"
    dmr_id = $2
    tlvLen = 3 + 4 + 3 + 1 + 1 + len(call) + 1                      # dmrID, repeaterID, tg, ts, cc, call, 0
    _sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    cmd = struct.pack("BBBBBBBBBBBBBB", 0x08, tlvLen, ((dmr_id >> 16) & 0xff),((dmr_id >> 8) & 0xff),(dmr_id & 0xff),0,0,0,0,0,0,0,0,0)[0:14] + call + chr(0)
    _sock.sendto(cmd, ('$SERVER', $TLV_PORT))
    _sock.close()
except:
    sys.stderr.write("setCallAndID: error sending command\n")
    exit(1)
END
    fi
}

#################################################################
# Tell AB to upload a file to the Mobile client
#################################################################
function pushFileToClient() {
    if [ ! -z "${DEBUG}" ]; then
        echo "remoteControlCommand pushFileToClient $1"
    else
        if [ ! -f $1 ]; then
            echo "File $1 does not exist, abort transfer"
            return
        fi
        size=`wc -c $1 | awk '{print $1}'`
        if (($size == 0)); then
            echo "file is empty, abort transfer"
            return
        fi

python3 - <<END
#!/usr/bin/env python
try:
    import sys, socket, struct

    TLV_TAG_FILE_XFER  = 11
    FILE_SUBCOMMAND_READ = 3
    name = "$1".encode("utf-8")+b'\x00'
    _sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    cmd = struct.pack("BBB", TLV_TAG_FILE_XFER, len(name)+1, FILE_SUBCOMMAND_READ)[0:3] + name
    _sock.sendto(cmd, ('$SERVER', $TLV_PORT))
    _sock.close()
except:
    sys.stderr.write("pushFileToClient: error pushing file $1\n")
    exit(1)
END
    fi
}

#################################################################
# Push a local file as a URL to DVSM.  The file is checked for
# whether it exists and has a size > 0 bytes. Arguments are
# Directory, Server IP and file name.
#################################################################
function pushLocalFileAsURLToClient() {

    if [ ! -f "$1/$3" ]; then
        echo "File $1/$3 does not exist, abort transfer"
        _ERRORCODE=$ERROR_FILE_NOT_FOUND
        return
    fi
    declare size=`wc -c "$1/$3" | awk '{print $1}'`
    if (($size == 0)); then
        echo "file is empty, abort transfer"
        _ERRORCODE=$ERROR_EMPTY_FILE
        return
    fi
    pushURLToClient "$2/$3"
}

#################################################################
# Send the URL of a file to download to DVSM.  DVSM knows that if
# the name begins with http it is a URL.
#################################################################
function pushURLToClient() {
python3 - <<END
#!/usr/bin/env python
try:
    import sys, socket, struct

    TLV_TAG_FILE_XFER  = 11
    FILE_SUBCOMMAND_READ = 3
    name = "$1".encode("utf-8")+b'\x00'
    _sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    cmd = struct.pack("BBB", TLV_TAG_FILE_XFER, len(name)+1, FILE_SUBCOMMAND_READ)[0:3] + name
    _sock.sendto(cmd, ('$SERVER', $TLV_PORT))
    _sock.close()
except:
    sys.stderr.write("pushURLToClient: error sending URL $1\n")
    exit(1)
END
}

#################################################################
# Parse the validated BrandMeister talk group database.
# TGList_BM.txt is maintained by downloadAndValidateBM() from the
# official BrandMeister API.  This keeps the DVSM/client list on the
# same validated dataset as the persistent MMDVM database.
#################################################################
function ParseTGFile() {
    declare _bm_source="${MMDVM_DIR}/$1"

    # collectProcessDataFiles may be called independently of "update".
    # If the persistent BM list is missing/empty, try to build it first.
    if [ ! -s "${_bm_source}" ]; then
        downloadAndValidateBM >/dev/null
    fi

python3 - <<END
try:
    import sys
    print("4000|||Unlink") # Make sure unlink is first in list
    f=open("$_bm_source", "r")
    if f.mode == 'r':
        lines = f.readlines()
        for line in lines:
            line = line.replace('\r', '')
            line = line.replace('\n', '')
            if not line or line[0:1] == '#':
                pass
            else:
                fields = line.split(';')
                if len(fields) >= 3 and fields[0].isdigit():
                    print(fields[0] + "|||" + fields[2].split('_TG')[0].replace('_',' '))
        f.close()
except Exception as e:
    sys.stderr.write("parseTGFile: error parsing $1: " + str(e) + "\n")
    print("ERROR|||ERROR")
    exit(1)
END
}

function ParseTGFileTGIF() {
    curl --fail -o "$NODE_DIR/$1" -s https://api.tgif.network/dmr/talkgroups/csv
python3 - <<END
try:
    import sys
    print("4000|||Unlink") # Make sure unlink is first in list
    f=open("$NODE_DIR/$1", "r")
    if f.mode == 'r':
        lines = f.readlines()
        for line in lines:
            line = line.replace('\r', '')
            line = line.replace('\n', '')
            if line[0:1] == '#':
                pass
            else:
                fields = line.split(',')
                print(fields[0] + "|||" + fields[1])
        f.close()
except:
    sys.stderr.write("downloadAndValidateTGIF: " + str(sys.exc_info()[1]) + "\n")
    print("ERROR|||ERROR")
    exit(1)
END
}

#################################################################
# Create a default DSTAR database.  I know this is probably not
# what you want, but I feel that a full list of all DSTAR nodes
# with all modules included would not be very useful.  So, just
# add your own favorites here (like I did).
#################################################################
function ParseDStarFile() {
    echo "       U|||Unlink"
    echo "REF001EL|||Echo"
    echo "       I|||Info"
    echo "REF001CL|||REF001 C"
    echo "REF004CL|||REF004 C"
    echo "REF012AL|||REF012 A"
    echo "XRF012AL|||XRF012 A"
    echo "REF014CL|||REF014 C"
    echo "REF030BL|||REF030 B"
    echo "REF030CL|||REF030 C"
    echo "REF038CL|||REF038 C"
    echo "REF050CL|||REF050 C"
    echo "REF058BL|||REF058 B"
    echo "REF078BL|||REF078 B"
    echo "REF078CL|||REF078 C"
    echo "DCS006FL|||DCS006 F"
    echo "DCS059AL|||DCS059 A"
}

#################################################################
# A general function to parse DVREF host files 
#################################################################
function ParseDVREFNodeFile() {
    local input_file="$1"
    local output_file="$2"

    curl -A "DVSwitch" -s "https://hostfiles.refcheck.radio/$1" -o "$input_file"
python3 - <<END

try:
    import json
    output_file = "$output_file"
    with open("$input_file", 'r') as f:
        dataFile = json.load(f)
        data = dataFile.get("reflectors")
    
    with open(output_file, 'w') as f:
        f.write(f"9999|||Unlink\n")
        for item in data:
            designator = item.get("designator")
            name = item.get("name")
            sponsor = item.get("sponsor")
            slug = item.get("slug")

            # Logic for the $$$$, $$$$ part
            if name and sponsor:
                description = f"{name}, {sponsor}"
            elif name:
                description = name
            elif sponsor:
                description = sponsor
            else:
                description = slug if slug else ""

            # Write the formatted line: ###|description
            f.write(f"{designator}|||{description}\n")
            
    print(f"File successfully created: {output_file}")

except Exception as e:
    print(f"An error occurred: {e}")
END
    rm "$input_file" 2>/dev/null
}

#################################################################
# Get the current ASL node list (used by allmon) and do a simple
# validation (look for my node number)
#################################################################
function DownloadAndValidateASLNodeList() {
    declare _OS=$(uname -s)
    curl --fail -s https://allmondb.allstarlink.org/allmondb.php | sed -e :a -e '$d;N;2,7ba' -e 'P;D' > "$NODE_DIR/$1"
    if [ ${_OS} == Darwin ]; then
        sed -i '' 's/||/|<None>|/g' "$NODE_DIR/$1"
    else
        sed -i 's/||/|<None>|/g' "$NODE_DIR/$1"
    fi
    declare isValid=`grep -i N4IRS "$NODE_DIR/$1"`
    if [ -z "${isValid}" ]; then
        rm "$NODE_DIR/$1"
        echo "ASL node list is not valid, ignoring"
    fi
}

#################################################################
# 
#################################################################
function collectProcessDataFiles() {

    declare gitURL="https://raw.githubusercontent.com/g4klx"
    echo "Processing NXDN"
    ParseDVREFNodeFile "NXDNHosts.json" "$NODE_DIR/NXDN_node_list.txt"

    echo "Processing P25"
    ParseDVREFNodeFile "P25Hosts.json" "$NODE_DIR/P25_node_list.txt"

    echo "Processing DMR"
    ParseTGFile TGList_BM.txt > $NODE_DIR/DMR_node_list.txt 2>/dev/null

    echo "Processing TGIF"
    ParseTGFileTGIF TGList_TGIF.txt > $NODE_DIR/TGIF_node_list.txt 2>/dev/null

    echo "Processing YSF"
    ParseDVREFNodeFile "YSFHosts.json" "$NODE_DIR/YSF_node_list.txt"

    echo "Processing DStar"
    ParseDStarFile DSTAR_Hosts.txt > $NODE_DIR/DSTAR_node_list.txt 2>/dev/null

    echo "Processing ASL"
    DownloadAndValidateASLNodeList node_list.txt 2>/dev/null
}

#################################################################
# Get all mobile data files, proces them into proper format and 
# push them to the device
#################################################################
function collectProcessPushDataFiles() {

    collectProcessDataFiles

    echo "Pushing NXDN"
    pushFileToClient "$NODE_DIR/NXDN_node_list.txt"

    echo "Pushing P25"
    pushFileToClient "$NODE_DIR/P25_node_list.txt"

    echo "Pushing DMR"
    pushFileToClient "$NODE_DIR/DMR_node_list.txt"

    echo "Pushing TGIF"
    pushFileToClient "$NODE_DIR/TGIF_node_list.txt"

    echo "Pushing YSF"
    pushFileToClient "$NODE_DIR/YSF_node_list.txt"

    echo "Pushing DStar"
    pushFileToClient "$NODE_DIR/DSTAR_node_list.txt"

    echo "Pushing ASL"
    pushFileToClient "$NODE_DIR/node_list.txt"
}

#################################################################
# Utility function to get  the primary IP address
#################################################################
function getMyIP() {
    declare _ip _line
    while IFS=$': \t' read -a _line ;do
        [ -z "${_line%inet}" ] &&
           _ip=${_line[${#_line[1]}>4?1:2]} &&
           [ "${_ip#127.0.0.1}" ] && echo $_ip && return 0
      done< <(LANG=C /sbin/ifconfig)
}

#################################################################
# Get all mobile data files, proces them into proper format and 
# push the URL to the device.  Starts a simple web server on port
# $HTTP_PORT (9042).
#################################################################
function collectProcessPushDataFilesHTTP() {

    declare processID=`ps aux | grep "python3 -m http.server $HTTP_PORT" | grep -v grep | awk '{print $2}'`
    kill $processID 2>/dev/null
    pushd "$NODE_DIR"
    python3 -m http.server $HTTP_PORT &
    popd
    declare _MYIP=`getMyIP`
    PSERVER="http://${_MYIP}:$HTTP_PORT"

    collectProcessDataFiles

    echo "Pushing NXDN"
    pushLocalFileAsURLToClient "$NODE_DIR" "$PSERVER" "NXDN_node_list.txt"
    sleep 5

    echo "Pushing P25"
    pushLocalFileAsURLToClient "$NODE_DIR" "$PSERVER" "P25_node_list.txt"
    sleep 5

    echo "Pushing DMR"
    pushLocalFileAsURLToClient "$NODE_DIR" "$PSERVER" "DMR_node_list.txt"
    sleep 5

    echo "Pushing TGIF"
    pushLocalFileAsURLToClient "$NODE_DIR" "$PSERVER" "TGIF_node_list.txt"
    sleep 5

    echo "Pushing YSF"
    pushLocalFileAsURLToClient "$NODE_DIR" "$PSERVER" "YSF_node_list.txt"
    sleep 5

    echo "Pushing DStar"
    pushLocalFileAsURLToClient "$NODE_DIR" "$PSERVER" "DSTAR_node_list.txt"
    sleep 5

    echo "Pushing ASL"
    pushLocalFileAsURLToClient "$NODE_DIR" "$PSERVER" "node_list.txt"
    sleep 10

    processID=`ps aux | grep "python3 -m http.server $HTTP_PORT" | grep -v grep | awk '{print $2}'`
    kill $processID 2>/dev/null

    sendMessage "Database update complete"

}

#################################################################
# Download and validate a file.  This function will use curl to download
# a file from a server and test for valid data.  The tests include
# a warning on download failure, and errors for file size and valid contents. 
#################################################################
function downloadAndValidate() {
    ${DEBUG} curl --fail -o "$MMDVM_DIR/$1" -s "http://www.pistar.uk/downloads/$2"
    if (( $? != 0 )); then
        echo "Warning, download failure"
        _ERRORCODE=$ERROR_FILE_NOT_FOUND
    fi
    if [ ! -f $MMDVM_DIR/$1 ]; then
        echo "Error, $1 file does not seem to exist"
        _ERRORCODE=$ERROR_INVALID_FILE
    else
        declare _fileSize=`wc -c $MMDVM_DIR/$1 | awk '{print $1}'`
        if (( ${_fileSize} < 10 )); then
            echo "Error, $1 file has no contents"
            _ERRORCODE=$ERROR_INVALID_FILE
        else
            declare isValid=`grep $3 "$MMDVM_DIR/$1"`
            if [ -z "$isValid" ]; then
                echo "Error, $1 file does not seem to be valid"
                _ERRORCODE=$ERROR_INVALID_FILE
            fi
        fi
    fi
}

#################################################################
# Download and validate the TGIF talkgroup database.
# Pull directly from the official TGIF API, convert the CSV data to
# the legacy DVSwitch/Pi-Star four-field talkgroup format, validate
# the converted file, then atomically replace the live database.
# A failed or invalid update never replaces the last known-good file.
#################################################################
function downloadAndValidateTGIF() {
    declare _tgif_url="https://api.tgif.network/dmr/talkgroups/csv"
    declare _tgif_file="${MMDVM_DIR}/TGList_TGIF.txt"
    declare _tgif_raw="${_tgif_file}.raw.$$"
    declare _tgif_tmp="${_tgif_file}.tmp.$$"
    declare _fileSize
    declare _lineCount

    rm -f "${_tgif_raw}" "${_tgif_tmp}"

    if ! ${DEBUG} curl --fail --location --silent --show-error \
        --connect-timeout 10 --max-time 60 --retry 3 --retry-delay 2 \
        -o "${_tgif_raw}" "${_tgif_url}"; then
        echo "Warning, TGIF API download failure; keeping existing TGList_TGIF.txt"
        rm -f "${_tgif_raw}" "${_tgif_tmp}"
        _ERRORCODE=$ERROR_FILE_NOT_FOUND
        return
    fi

    if [ ! -s "${_tgif_raw}" ]; then
        echo "Error, TGIF API returned an empty file; keeping existing TGList_TGIF.txt"
        rm -f "${_tgif_raw}" "${_tgif_tmp}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    if grep -Eqi '<!doctype|<html|<body' "${_tgif_raw}"; then
        echo "Error, TGIF API response appears to be an HTML/error page; keeping existing TGList_TGIF.txt"
        rm -f "${_tgif_raw}" "${_tgif_tmp}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    TGIF_RAW="${_tgif_raw}" TGIF_OUT="${_tgif_tmp}" python3 - <<'PYEND'
import csv
import os
import sys

raw_file = os.environ["TGIF_RAW"]
out_file = os.environ["TGIF_OUT"]
rows = []
seen = set()

try:
    with open(raw_file, "r", encoding="utf-8-sig", newline="") as src:
        reader = csv.reader(src)
        for row in reader:
            if not row or len(row) < 2:
                continue
            tg = row[0].strip()
            name = row[1].strip()
            if not tg.isdigit() or not name:
                continue
            # The legacy talkgroup format is semicolon-delimited, so keep
            # source text from creating extra fields or physical lines.
            name = name.replace(";", ",").replace("\r", " ").replace("\n", " ").strip()
            if not name or tg in seen:
                continue
            seen.add(tg)
            rows.append((int(tg), tg, name))

    # Sanity checks against stable TGIF talkgroups and a minimum useful list.
    ids = {tg for _, tg, _ in rows}
    if len(rows) < 100 or "101" not in ids or "31665" not in ids:
        raise ValueError(f"TGIF API data failed sanity checks ({len(rows)} valid talkgroups)")

    rows.sort(key=lambda item: item[0])
    with open(out_file, "w", encoding="utf-8", newline="\n") as dst:
        dst.write("# TGList_TGIF.txt generated from the official TGIF Network API\n")
        dst.write("# Source: https://api.tgif.network/dmr/talkgroups/csv\n")
        for _, tg, name in rows:
            dst.write(f"{tg};0;{name};TG{tg}\n")
except Exception as exc:
    sys.stderr.write(f"TGIF database conversion failed: {exc}\n")
    try:
        os.remove(out_file)
    except FileNotFoundError:
        pass
    sys.exit(1)
PYEND
    if (( $? != 0 )); then
        echo "Error, TGIF API data could not be converted; keeping existing TGList_TGIF.txt"
        rm -f "${_tgif_raw}" "${_tgif_tmp}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    rm -f "${_tgif_raw}"

    if [ ! -s "${_tgif_tmp}" ]; then
        echo "Error, converted TGList_TGIF.txt is empty; keeping existing file"
        rm -f "${_tgif_tmp}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    _fileSize=$(wc -c < "${_tgif_tmp}")
    _lineCount=$(grep -Ec '^[0-9]+;0;[^;]+;TG[0-9]+$' "${_tgif_tmp}")

    if (( _fileSize < 1000 || _lineCount < 100 )); then
        echo "Error, converted TGList_TGIF.txt failed size/record validation (${_fileSize} bytes, ${_lineCount} records); keeping existing file"
        rm -f "${_tgif_tmp}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    if ! grep -q '^101;0;.*;TG101$' "${_tgif_tmp}" || \
       ! grep -q '^31665;0;.*;TG31665$' "${_tgif_tmp}"; then
        echo "Error, converted TGList_TGIF.txt failed known-talkgroup validation; keeping existing file"
        rm -f "${_tgif_tmp}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    if ! mv -f "${_tgif_tmp}" "${_tgif_file}"; then
        echo "Error, unable to install validated TGList_TGIF.txt"
        rm -f "${_tgif_tmp}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    echo "TGList_TGIF.txt downloaded from TGIF API and validated successfully (${_lineCount} talkgroups, ${_fileSize} bytes)"
}

#################################################################
# Download and validate the YSF reflector host database.
# Pull the native YSFHosts.txt directly from DVRef/RefCheck using
# the same DVSwitch user-agent used by the 1.6.3 DVRef JSON path.
# Validate real reflector records before atomically replacing the
# live file used by YSFGateway. A failed update preserves the last
# known-good YSFHosts.txt.
#################################################################
function downloadAndValidateYSF() {
    declare _ysf_url="https://hostfiles.refcheck.radio/YSFHosts.txt"
    declare _ysf_file="${MMDVM_DIR}/YSFHosts.txt"
    declare _ysf_tmp="${_ysf_file}.tmp.$$"
    declare _fileSize
    declare _lineCount

    rm -f "${_ysf_tmp}"

    if ! ${DEBUG} curl --fail --location --silent --show-error \
        --user-agent "DVSwitch" \
        --connect-timeout 10 --max-time 60 --retry 3 --retry-delay 2 \
        -o "${_ysf_tmp}" "${_ysf_url}"; then
        echo "Warning, YSFHosts.txt download failure; keeping existing YSFHosts.txt"
        rm -f "${_ysf_tmp}"
        _ERRORCODE=$ERROR_FILE_NOT_FOUND
        return
    fi

    if [ ! -s "${_ysf_tmp}" ]; then
        echo "Error, downloaded YSFHosts.txt is empty; keeping existing file"
        rm -f "${_ysf_tmp}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    if grep -Eqi '<!doctype|<html|<body' "${_ysf_tmp}"; then
        echo "Error, YSFHosts.txt response appears to be HTML; keeping existing file"
        rm -f "${_ysf_tmp}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    _fileSize=$(wc -c < "${_ysf_tmp}")
    _lineCount=$(awk -F';' '
        /^[0-9][0-9][0-9][0-9][0-9];/ && NF >= 5 && $2 != "" && $4 != "" && $5 ~ /^[0-9]+$/ { count++ }
        END { print count+0 }
    ' "${_ysf_tmp}")

    # A real YSF host database contains hundreds of reflector records.
    # This rejects zero-byte, truncated, login/error, and structurally
    # incorrect files while allowing harmless comments/header lines.
    if (( _fileSize < 10000 || _lineCount < 500 )); then
        echo "Error, downloaded YSFHosts.txt failed size/record validation (${_fileSize} bytes, ${_lineCount} reflector records); keeping existing file"
        rm -f "${_ysf_tmp}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    if ! mv -f "${_ysf_tmp}" "${_ysf_file}"; then
        echo "Error, unable to install validated YSFHosts.txt"
        rm -f "${_ysf_tmp}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    echo "YSFHosts.txt downloaded from DVRef/RefCheck and validated successfully (${_lineCount} reflectors, ${_fileSize} bytes)"
}

#################################################################
# Download and validate the P25 reflector host database.
# Pull the native P25Hosts.txt directly from DVRef/RefCheck.
# Validate real P25 records before atomically replacing the live
# file used by P25Gateway. A failed update preserves the last
# known-good P25Hosts.txt.
#################################################################
function downloadAndValidateP25() {
    declare _p25_url="https://hostfiles.refcheck.radio/P25Hosts.txt"
    declare _p25_file="${MMDVM_DIR}/P25Hosts.txt"
    declare _p25_tmp="${_p25_file}.tmp.$$"
    declare _fileSize
    declare _lineCount

    rm -f "${_p25_tmp}"

    if ! ${DEBUG} curl --fail --location --silent --show-error \
        --user-agent "DVSwitch" \
        --connect-timeout 10 --max-time 60 --retry 3 --retry-delay 2 \
        -o "${_p25_tmp}" "${_p25_url}"; then
        echo "Warning, P25Hosts.txt download failure; keeping existing P25Hosts.txt"
        rm -f "${_p25_tmp}"
        _ERRORCODE=$ERROR_FILE_NOT_FOUND
        return
    fi

    if [ ! -s "${_p25_tmp}" ]; then
        echo "Error, downloaded P25Hosts.txt is empty; keeping existing file"
        rm -f "${_p25_tmp}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    if grep -Eqi '<!doctype|<html|<body' "${_p25_tmp}"; then
        echo "Error, P25Hosts.txt response appears to be HTML; keeping existing file"
        rm -f "${_p25_tmp}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    _fileSize=$(wc -c < "${_p25_tmp}")
    _lineCount=$(awk '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        NF >= 3 && $1 ~ /^[0-9]+$/ && $2 != "" && $3 ~ /^[0-9]+$/ { count++ }
        END { print count+0 }
    ' "${_p25_tmp}")

    # P25Hosts.txt records are: talkgroup host-or-address port.
    # Reject empty, truncated, HTML, or structurally invalid downloads.
    if (( _fileSize < 500 || _lineCount < 20 )); then
        echo "Error, downloaded P25Hosts.txt failed size/record validation (${_fileSize} bytes, ${_lineCount} reflector records); keeping existing file"
        rm -f "${_p25_tmp}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    if ! mv -f "${_p25_tmp}" "${_p25_file}"; then
        echo "Error, unable to install validated P25Hosts.txt"
        rm -f "${_p25_tmp}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    echo "P25Hosts.txt downloaded from DVRef/RefCheck and validated successfully (${_lineCount} reflectors, ${_fileSize} bytes)"
}

#################################################################
# Download and validate the NXDN reflector host database.
# Pull the native NXDNHosts.txt directly from DVRef/RefCheck.
# Validate real NXDN records before atomically replacing the live
# file used by NXDNGateway. A failed update preserves the last
# known-good NXDNHosts.txt.
#################################################################
function downloadAndValidateNXDN() {
    declare _nxdn_url="https://hostfiles.refcheck.radio/NXDNHosts.txt"
    declare _nxdn_file="${MMDVM_DIR}/NXDNHosts.txt"
    declare _nxdn_tmp="${_nxdn_file}.tmp.$$"
    declare _fileSize
    declare _lineCount

    rm -f "${_nxdn_tmp}"

    if ! ${DEBUG} curl --fail --location --silent --show-error \
        --user-agent "DVSwitch" \
        --connect-timeout 10 --max-time 60 --retry 3 --retry-delay 2 \
        -o "${_nxdn_tmp}" "${_nxdn_url}"; then
        echo "Warning, NXDNHosts.txt download failure; keeping existing NXDNHosts.txt"
        rm -f "${_nxdn_tmp}"
        _ERRORCODE=$ERROR_FILE_NOT_FOUND
        return
    fi

    if [ ! -s "${_nxdn_tmp}" ]; then
        echo "Error, downloaded NXDNHosts.txt is empty; keeping existing file"
        rm -f "${_nxdn_tmp}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    if grep -Eqi '<!doctype|<html|<body' "${_nxdn_tmp}"; then
        echo "Error, NXDNHosts.txt response appears to be HTML; keeping existing file"
        rm -f "${_nxdn_tmp}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    _fileSize=$(wc -c < "${_nxdn_tmp}")
    _lineCount=$(awk '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        NF >= 3 && $1 ~ /^[0-9]+$/ && $2 != "" && $3 ~ /^[0-9]+$/ { count++ }
        END { print count+0 }
    ' "${_nxdn_tmp}")

    # NXDNHosts.txt records are: talkgroup host-or-address port.
    # Reject empty, truncated, HTML, or structurally invalid downloads.
    if (( _fileSize < 500 || _lineCount < 20 )); then
        echo "Error, downloaded NXDNHosts.txt failed size/record validation (${_fileSize} bytes, ${_lineCount} reflector records); keeping existing file"
        rm -f "${_nxdn_tmp}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    # Worldwide TG 65000 is a long-standing NXDN reflector entry and
    # provides an additional sanity check that the expected dataset arrived.
    if ! awk '$1 == 65000 && $3 ~ /^[0-9]+$/ { found=1 } END { exit(found ? 0 : 1) }' "${_nxdn_tmp}"; then
        echo "Error, downloaded NXDNHosts.txt failed known-reflector validation; keeping existing file"
        rm -f "${_nxdn_tmp}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    if ! mv -f "${_nxdn_tmp}" "${_nxdn_file}"; then
        echo "Error, unable to install validated NXDNHosts.txt"
        rm -f "${_nxdn_tmp}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    echo "NXDNHosts.txt downloaded from DVRef/RefCheck and validated successfully (${_lineCount} reflectors, ${_fileSize} bytes)"
}

#################################################################
# Download BrandMeister talk groups from the official BrandMeister
# v2 API, convert them to the existing DVSwitch TGList_BM.txt format,
# validate both source data and converted output, then atomically
# replace the live database.  A failed/invalid update never replaces
# the last known-good file.
#################################################################
function downloadAndValidateBM() {
    declare _bm_url="https://api.brandmeister.network/v2/talkgroup"
    declare _bm_file="${MMDVM_DIR}/TGList_BM.txt"
    declare _bm_raw="${_bm_file}.raw.$$"
    declare _bm_new="${_bm_file}.new.$$"
    declare _recordCount _fileSize

    rm -f "${_bm_raw}" "${_bm_new}"

    if ! ${DEBUG} curl --fail --location --show-error \
        --connect-timeout 10 --max-time 60 --retry 3 --retry-delay 2 \
        -H 'Accept: application/json' \
        -o "${_bm_raw}" -s "${_bm_url}"; then
        echo "Warning, BrandMeister talkgroup API download failure; keeping existing TGList_BM.txt"
        rm -f "${_bm_raw}" "${_bm_new}"
        _ERRORCODE=$ERROR_FILE_NOT_FOUND
        return
    fi

    if [ ! -s "${_bm_raw}" ]; then
        echo "Error, BrandMeister API returned an empty file; keeping existing TGList_BM.txt"
        rm -f "${_bm_raw}" "${_bm_new}"
        _ERRORCODE=$ERROR_EMPTY_FILE
        return
    fi

    # Parse the API JSON and convert to the exact four-field format already
    # consumed by DVSwitch: ID;Option;Name;Description
    # Be tolerant of harmless API field-name capitalization changes while
    # requiring a numeric ID and non-empty name for every accepted record.
    BM_RAW="${_bm_raw}" BM_NEW="${_bm_new}" python3 - <<'END_BM'
import json, os, sys

raw = os.environ["BM_RAW"]
out = os.environ["BM_NEW"]

try:
    with open(raw, "r", encoding="utf-8-sig") as f:
        data = json.load(f)
except Exception as e:
    sys.stderr.write("BrandMeister JSON parse error: %s\n" % e)
    sys.exit(2)

# BrandMeister's public endpoint has appeared in more than one JSON shape
# over time.  Accept the known safe forms:
#   1) a list of objects containing ID/Name
#   2) a wrapper object containing a list under talkgroups/data/results
#   3) a dictionary keyed by numeric talkgroup ID, with either a string name
#      or an object containing Name/name
# This is deliberately strict about numeric IDs and non-empty names.
records = {}

def add_record(tg, name):
    if tg is None or name is None:
        return
    tg = str(tg).strip()
    name = str(name).strip()
    if not tg.isdigit() or not name:
        return
    number = int(tg)
    if number < 1 or number > 9999999:
        return
    name = " ".join(name.replace(";", ",").replace("\r", " ").replace("\n", " ").split())
    if name:
        records[number] = name

def parse_item(item, fallback_id=None):
    if isinstance(item, str):
        add_record(fallback_id, item)
        return
    if not isinstance(item, dict):
        return

    tg = fallback_id
    for key in ("ID", "id", "TalkGroup", "talkgroup", "tgid", "group"):
        if key in item and item[key] is not None:
            tg = item[key]
            break

    name = None
    for key in ("Name", "name", "Description", "description"):
        if key in item and item[key] is not None:
            name = item[key]
            break

    add_record(tg, name)

if isinstance(data, list):
    for item in data:
        parse_item(item)
elif isinstance(data, dict):
    wrapped = None
    for key in ("talkgroups", "data", "results"):
        if isinstance(data.get(key), list):
            wrapped = data[key]
            break

    if wrapped is not None:
        for item in wrapped:
            parse_item(item)
    else:
        # Numeric-key dictionary form: {"91": "World-wide", ...}
        # or {"91": {"Name": "World-wide"}, ...}
        for key, value in data.items():
            if str(key).strip().isdigit():
                parse_item(value, fallback_id=key)
else:
    sys.stderr.write("BrandMeister API response is not valid JSON talkgroup data\n")
    sys.exit(3)

if not records:
    sys.stderr.write("BrandMeister API response contained no valid talkgroup records\n")
    sys.exit(3)

# BrandMeister normally has well over 1,000 registered groups.  A much smaller
# response is almost certainly truncated/broken and must not replace a good DB.
if len(records) < 1000:
    sys.stderr.write("BrandMeister API returned too few valid talkgroups: %d\n" % len(records))
    sys.exit(4)

# Stable, globally-known registry entries provide content sanity checks.
for required in (91, 3100):
    if required not in records:
        sys.stderr.write("BrandMeister API response is missing required TG %d\n" % required)
        sys.exit(5)

with open(out, "w", encoding="utf-8", newline="\n") as f:
    f.write("# ID;Option;Name;Description\n")
    f.write("# Option: TG:0, REF:1, PC:2\n")
    for tg in sorted(records):
        f.write(f"{tg};0;{records[tg]};TG{tg}\n")

END_BM

    declare _py_rc=$?
    if (( _py_rc != 0 )); then
        echo "Error, BrandMeister API data failed validation/conversion; keeping existing TGList_BM.txt"
        rm -f "${_bm_raw}" "${_bm_new}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    if [ ! -s "${_bm_new}" ]; then
        echo "Error, converted TGList_BM.txt is empty; keeping existing file"
        rm -f "${_bm_raw}" "${_bm_new}"
        _ERRORCODE=$ERROR_EMPTY_FILE
        return
    fi

    _recordCount=$(awk -F';' '$1 ~ /^[0-9]+$/ && $2 == "0" && NF >= 4 {count++} END {print count+0}' "${_bm_new}")
    _fileSize=$(wc -c < "${_bm_new}")

    if (( _recordCount < 1000 )); then
        echo "Error, converted TGList_BM.txt has too few valid records (${_recordCount}); keeping existing file"
        rm -f "${_bm_raw}" "${_bm_new}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    if (( _fileSize < 20000 )); then
        echo "Error, converted TGList_BM.txt is unexpectedly small (${_fileSize} bytes); keeping existing file"
        rm -f "${_bm_raw}" "${_bm_new}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    # Verify the final format and the same known talkgroups after conversion.
    if ! awk -F';' '$1 == 91 && $2 == 0 && $4 == "TG91" {a=1}
                    $1 == 3100 && $2 == 0 && $4 == "TG3100" {b=1}
                    END {exit(a && b ? 0 : 1)}' "${_bm_new}"; then
        echo "Error, converted TGList_BM.txt failed known-talkgroup validation; keeping existing file"
        rm -f "${_bm_raw}" "${_bm_new}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    if ! mv -f "${_bm_new}" "${_bm_file}"; then
        echo "Error, unable to install validated TGList_BM.txt"
        rm -f "${_bm_raw}" "${_bm_new}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    rm -f "${_bm_raw}"
    echo "TGList_BM.txt downloaded from BrandMeister API and validated successfully (${_recordCount} talkgroups, ${_fileSize} bytes)"
}

#################################################################
# Download and validate D-Star reflector host databases.
# DCS, DPlus (REF), and DExtra (XRF) use the current Pi-Star
# host-file feeds; XLX uses DVRef/RefCheck. D-Star uses separate
# host files for each reflector family.
#
# Each file is downloaded to a temporary file, checked for HTTP
# success, non-empty/non-HTML content, expected native record
# structure, realistic record count/size, then atomically moved
# into place.  A bad update never replaces the last known-good file.
#################################################################
function downloadAndValidateDStar() {
    declare _name="$1"
    declare _kind="$2"
    declare _url
    declare _sourceLabel

    case "${_kind}" in
        XLX)
            _url="https://hostfiles.refcheck.radio/${_name}"
            _sourceLabel="DVRef/RefCheck"
            ;;
        DCS|DPLUS|DEXTRA)
            _url="https://www.pistar.uk/downloads/${_name}"
            _sourceLabel="Pi-Star"
            ;;
        *)
            echo "Error, unknown D-Star host-file type ${_kind}"
            _ERRORCODE=$ERROR_INVALID_ARGUMENT
            return
            ;;
    esac
    declare _live="${MMDVM_DIR}/${_name}"
    declare _tmp="${_live}.new.$$"
    declare _recordCount=0
    declare _fileSize=0

    rm -f "${_tmp}"

    if ! ${DEBUG} curl --fail --location --show-error \
        --connect-timeout 10 --max-time 60 --retry 3 --retry-delay 2 \
        -A "DVSwitch" -o "${_tmp}" -s "${_url}"; then
        echo "Warning, ${_name} download failure from ${_sourceLabel}; keeping existing file"
        rm -f "${_tmp}"
        _ERRORCODE=$ERROR_FILE_NOT_FOUND
        return
    fi

    if [ ! -s "${_tmp}" ]; then
        echo "Error, ${_name} download is empty; keeping existing file"
        rm -f "${_tmp}"
        _ERRORCODE=$ERROR_EMPTY_FILE
        return
    fi

    if grep -Eiq '<!doctype|<html|<body' "${_tmp}"; then
        echo "Error, ${_name} appears to contain HTML/error data; keeping existing file"
        rm -f "${_tmp}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    case "${_kind}" in
        DCS)
            # Native DCS host records: DCSnnn <hostname-or-IP> [optional fields]
            _recordCount=$(awk '
                /^[[:space:]]*#/ || /^[[:space:]]*$/ {next}
                $1 ~ /^DCS[0-9A-Z][0-9A-Z][0-9A-Z]$/ && NF >= 2 {c++}
                END {print c+0}' "${_tmp}")
            ;;
        DPLUS)
            # Native DPlus host records: REFnnn <hostname-or-IP> [optional fields]
            _recordCount=$(awk '
                /^[[:space:]]*#/ || /^[[:space:]]*$/ {next}
                $1 ~ /^REF[0-9A-Z][0-9A-Z][0-9A-Z]$/ && NF >= 2 {c++}
                END {print c+0}' "${_tmp}")
            ;;
        DEXTRA)
            # Native DExtra host records: XRFnnn <hostname-or-IP> [optional fields]
            _recordCount=$(awk '
                /^[[:space:]]*#/ || /^[[:space:]]*$/ {next}
                $1 ~ /^XRF[0-9A-Z][0-9A-Z][0-9A-Z]$/ && NF >= 2 {c++}
                END {print c+0}' "${_tmp}")
            ;;
        XLX)
            # Native XLXHosts format is semicolon-delimited and begins with
            # a three-character reflector designator, e.g. 001;host;...
            _recordCount=$(awk -F';' '
                /^[[:space:]]*#/ || /^[[:space:]]*$/ {next}
                $1 ~ /^[0-9A-Z][0-9A-Z][0-9A-Z]$/ && NF >= 2 && length($2) > 0 {c++}
                END {print c+0}' "${_tmp}")
            ;;
        *)
            echo "Error, unknown D-Star host-file type ${_kind}"
            rm -f "${_tmp}"
            _ERRORCODE=$ERROR_INVALID_ARGUMENT
            return
            ;;
    esac

    _fileSize=$(wc -c < "${_tmp}")

    # Deliberately conservative lower bounds: enough to reject a truncated
    # or error response without tying validity to any one reflector number.
    if (( _recordCount < 20 )); then
        echo "Error, ${_name} has too few valid ${_kind} records (${_recordCount}); keeping existing file"
        rm -f "${_tmp}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    if (( _fileSize < 500 )); then
        echo "Error, ${_name} is unexpectedly small (${_fileSize} bytes); keeping existing file"
        rm -f "${_tmp}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    if ! mv -f "${_tmp}" "${_live}"; then
        echo "Error, unable to install validated ${_name}"
        rm -f "${_tmp}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    echo "${_name} downloaded from ${_sourceLabel} and validated successfully (${_recordCount} reflectors, ${_fileSize} bytes)"
}

#################################################################
# Download all user databases
#################################################################
function downloadDatabases() {
    if [ -d "${MMDVM_DIR}" ] && [ -d "${AB_DIR}" ]; then

        ${DEBUG} curl -s -N "https://database.radioid.net/static/user.csv" | awk -F, 'NR>1 {if ($1 > "") print $1,$2,$3}' > "${MMDVM_DIR}/DMRIds.dat"
        ${DEBUG} curl -s -N "https://database.radioid.net/static/user.csv" | awk -F, 'BEGIN{OFS=",";} NR>1 {if ($1 > "") print $1,$2,$3}' > "${AB_DIR}/subscriber_ids.csv"
        ${DEBUG} curl -s -N "https://database.radioid.net/static/nxdn.csv" > "${MMDVM_DIR}/NXDN.csv"
        ${DEBUG} curl -s -N "http://www.pistar.uk/downloads/DMR_Hosts.txt" > "${MMDVM_DIR}/DMR_Hosts.txt"

        downloadAndValidateNXDN
        downloadAndValidateP25
        downloadAndValidateBM
        downloadAndValidateYSF

        downloadAndValidateTGIF
# TG list direct from BM
# curl -X 'GET' 'https://api.brandmeister.network/v2/talkgroup' -H 'accept: */*'
# TG list from TGIF
# curl -X 'GET' 'https://api.tgif.network/dmr/talkgroups/json'
# TG list from FreeDMR
# curl -X 'GET' 'https://freedmr.cymru/talkgroups/talkgroup_ids_json.php'

        downloadAndValidate "FCSRooms.txt" "FCS_Hosts.txt" "FCS00106"
        downloadAndValidateDStar "DCS_Hosts.txt" "DCS"
        downloadAndValidateDStar "DPlus_Hosts.txt" "DPLUS"
        downloadAndValidateDStar "DExtra_Hosts.txt" "DEXTRA"
        downloadAndValidateDStar "XLXHosts.txt" "XLX"
        downloadAndValidate "APRS_Hosts.txt" "APRS_Hosts.txt" "noam.aprs2.net"

        declare isValid=`grep 3113043 "${MMDVM_DIR}/DMRIds.dat"`
        if [ -z "$isValid" ]; then

            ${DEBUG} curl -s -N "http://registry.dstar.su/dmr/DMRIds.php" > "${MMDVM_DIR}/DMRIds.dat"
            ${DEBUG} curl -s -N "http://registry.dstar.su/dmr/DMRIds.php" | awk -F, 'BEGIN{FS=" ";OFS=",";} NR>1 {if ($1 > "") print $1,$2,$3}' > "${AB_DIR}/subscriber_ids.csv"

            isValid=`grep 3113043 "${MMDVM_DIR}/DMRIds.dat"`
            if [ -z "$isValid" ]; then
                echo "Error, DMR ID file does not seem to be valid"
                _ERRORCODE=$ERROR_INVALID_FILE
            fi
        fi
    else
        echo "Destination directory does not exist, aborting"
        _ERRORCODE=$ERROR_DIR_NOT_FOUND
    fi
}

#################################################################
# Set digital mode of AB/MB getting the proper ports from DVSwitch.ini
#################################################################
function setMode() {
    if [ $# -eq 0 ]; then   # No argument passed, just return the current value
        echo `getABInfoValue tlv ambe_mode`
    else
        declare _MODE=`echo $1 | tr '[:lower:]' '[:upper:]'`
        if [[ "|DMR|YSF|P25|NXDN|DSTAR|ASL|STFU|" == *"$_MODE"* ]]; then
            ${DEBUG} setTLVRxPort 30000  # cause AB to stop listening
            _MBTX=`parseIniFile "$DVSWITCH_INI" "$_MODE" "TXPort"`
            _MBRX=`parseIniFile "$DVSWITCH_INI" "$_MODE" "RXPort"`
            if [ ! -z $_MBTX ]; then
                sendMessage "Setting mode to $_MODE"
                ${DEBUG} setAmbeMode $_MODE
                ${DEBUG} setTLVTxPort ${_MBRX}
                ${DEBUG} setTLVRxPort ${_MBTX}
                if [ $# -ge 2 ]; then ${DEBUG} setTLVGain $2; setTLVAudioType AUDIO_USE_GAIN; fi
                if [ $# -ge 3 ]; then ${DEBUG} setUSRPGain $3; setUSRPAudioType AUDIO_USE_GAIN; fi
                ${DEBUG} getInfo
            else
                echo "Error, DVSwitch.ini file not found"
                _ERRORCODE=$ERROR_FILE_NOT_FOUND
            fi
        else
            echo "Error, Mode must be DMR or YSF or P25 or DSTAR, NXDN, ASL or STFU"
            _ERRORCODE=$ERROR_INVALID_ARGUMENT
        fi
    fi
}

#################################################################
# Show pretty ABInfo json file
#################################################################
function prettyPrintInfo() {
    declare _abname=`getABInfoFileName`
    if [ -f ${_abname} ]; then
        python3 -mjson.tool ${_abname} 
    else
        echo ABInfo file not found
    fi
}

#################################################################
# Lookup info in database file
#################################################################
function lookup() {
    declare databaseName="${MMDVM_DIR}/DMRIds.dat"
    if [ -f "${databaseName}" ]; then
        found=`grep -i $1 "${databaseName}"`
        if [ -z "$found" ]; then
            _ERRORCODE=$ERROR_LOOKUP_FAILED
        else
            echo $found
        fi
    else
        echo DMR ID database file not found at ${databaseName}
        _ERRORCODE=$ERROR_LOOKUP_FAILED
    fi
}

#################################################################
# Get version information from AB and MB
#################################################################
function appVersion() {
    if [ $# -eq 0 ]; then
        echo "dvswitch.sh version $SCRIPT_VERSION"
    else
        case $1 in
            ab|AB|Analog_Bridge)
                if [ -f "/opt/Analog_Bridge/Analog_Bridge" ]; then
                    "/opt/Analog_Bridge/Analog_Bridge" -v
                else
                    declare _ver=`getABInfoValue ab version`
                    echo "Analog_Bridge version ${_ver}"
                fi
            ;;
            mb|MB|MMDVM_Bridge)
                if [ -f "/opt/MMDVM_Bridge/MMDVM_Bridge" ]; then
                    "/opt/MMDVM_Bridge/MMDVM_Bridge" -v
                else
                    echo "MMDVM_Bridge version UNKNOWN"
                fi
            ;;
            gw|GW)
                for gw in P25Gateway NXDNGateway YSFGateway; do
                    if [ -f "/opt/$gw/$gw" ]; then
                        "/opt/$gw/$gw" -v
                    fi
                done 
            ;;
            path)
                if [ -f "$2" ]; then
                    "$2" -v
                fi
            ;;
            all|ALL)
                appVersion
                for app in ab mb gw; do
                    appVersion $app
                done
                for app in Analog_Reflector STFU; do
                    appVersion path "/opt/${app}/${app}"
                done                
            ;;
        esac
    fi
}

#################################################################
# Echo the list of "enabled" modes in MB.ini
#################################################################
function getEnabledModes() {
    # For each mode, disable the main section and the network
    declare _MODE=""
    declare _NET=""
    declare enabledModes=""
    for mode in DMR "System Fusion" P25 D-Star NXDN; do
        _MODE=`parseIniFile "$MMDVM_INI" "${mode}" "Enable"`
        _NET=`parseIniFile "$MMDVM_INI" "${mode} Network" "Enable"`
        #echo "${mode} mode = ${_MODE} and Network = ${_NET}"
        if [ ${_MODE} == "1" ] && [ ${_NET} == "1" ]; then
            enabledModes=`echo ${enabledModes}${mode}" " `
        fi
    done
    echo "$1${enabledModes}"
}

#################################################################
# Print out the owner for a specified UDP port
#################################################################
function getUDPPortOwner() {
    if [ -z "$1" ]; then
        echo "Argument required: port number"
        _ERRORCODE=$ERROR_INVALID_ARGUMENT
    else
        declare port=":$1"
        declare _OS=$(uname -s)

        if [ ${_OS} == Darwin ]; then
            declare pid=$(lsof -i udp$port -P +c 0 | awk 'NR>1 {print $2}')
            if [ -z "$pid" ]; then
                echo "No processes listening on port $port"
            else
                ps -f $pid | awk 'NR>1 {print $8 " " $9 " " $10}'
            fi
        else
            declare pid=$(sudo netstat -unap | grep "$port" | awk '{print $6}' | cut -d'/' -f1)
            if [ -z "$pid" ]; then
                echo "No processes listening on port $port"
            else
                ps -f $pid | awk 'NR>1 {print $9 " " $10 " " $11}'
            fi
        fi
    fi
}

#################################################################
# Print out the ports owned by a specified process
#################################################################
function getUDPPortsForProcess() {
    if [ -z "$1" ]; then
        echo "Argument required: process name"
        _ERRORCODE=$ERROR_INVALID_ARGUMENT
    else
        declare process="$1"
        declare _OS=$(uname -s)

        set -f;
        if [ ${_OS} == Darwin ]; then
            declare ports=($(lsof -i udp -P +c 0 | grep -i "${process:0:14}" | awk '{if ($9 != "*:*") print $9}' | cut -d':' -f2))
            if [ ${#ports[@]} -gt 0 ]; then
                echo "$process owns UDP ports: ${ports[@]}"
            fi
        else
            declare ports=($(sudo netstat -unap | grep -i "${process:0:14}" | awk '{split($4, a, ":"); print a[2]}'))
            if [ ${#ports[@]} -gt 0 ]; then
                echo "$process owns UDP ports: ${ports[@]}"
            fi
        fi
        set +f;
    fi
}

#################################################################
# Print out the ports for all DVSwitch processes
#################################################################
function getUDPPortsForDVSwitch() {
    for i in Analog_Bridge MMDVM_Bridge Quantar_Bridge Analog_Reflector STFU P25Gateway NXDNGateway DMRGateway YSFGateway ircddbgateway YSFParrot NXDNParrot md380-emu; do
        getUDPPortsForProcess "$i"
    done
}

#################################################################
# 
#################################################################
function updateINIFileValue() {
    declare _file="$1"
    declare _section="$2"
    declare _tag="$3"
    declare _value="${@:4}"

    if [ $# -ge 2 ]; then       # Do we have the correct number of arguments?
        if [ -f ${_file} ]; then    # Check if the file exists (better error message then parseIniFile)
            declare _secFound=$(grep -i "^\\[${_section}\\]" "${_file}")
            if [ ! -z "${_secFound}" ]; then  # See if the section exists
                if [ ! -z ${_tag} ]; then
                    declare _tagLine=$(sed  -n "/^\[${_section}\]/,/^\[/ p" "${_file}" | sed -n "/${_tag}/p")
                    if [ ! -z "${_tagLine}" ]; then
                        if [ ! -z "${_value}" ]; then
                            declare _oldValue=`parseIniFile "${_file}" "${_section}" "${_tag}"`
                            declare _oldLine="^${_tag}.*=.*${_oldValue}"
                            declare _equal=`[[ "${_tagLine}" == *" = "* ]] && echo " = " || echo "="`
                            declare _newLine="${_tag}${_equal}${_value}"
                            sed -i -e "/^\[${_section}\]/,/^\[/ s/${_oldLine}/${_newLine}/i" "${_file}"
                        else
                            echo "${_tagLine}"
                        fi
                    else
                        echo "Error Tag \"${_tag}\" was not found in section \"${_section}\" of file \"${_file}\""
                        _ERRORCODE=$ERROR_INI_FAILURE
                    fi
                else
                    declare _fullSection=$(sed  -n "/^\[${_section}\]/,/^\[/ p" "${_file}")
                    echo "${_fullSection}"
                fi
            else
                echo "Error, section \"${_section}\" was not found in file \"${_file}\""
                _ERRORCODE=$ERROR_INI_FAILURE
            fi
        else
            echo "INI File \"${_file}\" not found"
            _ERRORCODE=$ERROR_INI_FAILURE
        fi
    else
        echo "Error, argument number: file section {tag} {value}"
        _ERRORCODE=$ERROR_INI_FAILURE
    fi
}

#################################################################
# 
#################################################################
function setGpsToIP() {
    declare ip=$(curl -s ifconfig.me)
    declare json=$(curl -s -L ipvigilante.com/$ip)
latlon=(`python3 - <<END
#!/usr/bin/env python
try:
    import json, os, sys
    json = json.loads('$json')
    print(json['data']['latitude'])
    print(json['data']['longitude'])
except:
    pass
END
`)
    remoteControlCommand "gps=${latlon[0]},${latlon[1]}"
}

function parseAnyIniFile() {
    if [ $# -ge 2 ]; then
        case $1 in
            AB|ab)
                parseIniFile "/opt/Analog_Bridge/Analog_Bridge.ini" $2 $3
            ;;
            MB|mb)
                parseIniFile "${MMDVM_INI}" $3 $3
            ;;
            DV|dv)
                parseIniFile "${DVSWITCH_INI}" $2 $3
            ;;
            *)
                if [ -f "$1" ]; then
                    parseIniFile "$1" $2 $3
                else
                    echo "INI file $1 was not found"
                fi
            ;;
        esac
    else
        echo "Wrong number of arguments: [path | AB | MB | DV] [section] [tag]"
    fi
}
#################################################################
# Show usage string to someone who wants to know the available options
#################################################################
function usage() {
    echo -e "Usage:"
    echo -e "$0 \n\t { version | mode | tune | ambesize | ambemode | slot | update | tlvAudio | usrpAudio | usrpCodec | tlvPorts | "
    echo -e "\t   info | show | lookup | mute | message | macro |"
    echo -e "\t   pushfile | collectProcessDataFiles | collectProcessPushDataFiles | pushurl | collectProcessPushDataFilesHTTP }"
    echo -e "\t version {AB|MB|GW|ALL}\t\t\t\t Show version of dvswitch.sh, Analog_Bridge or MMDVM_Bridge"
    echo -e "\t mode {DMR|NXDN|P25|YSF|DSTAR} \t\t\t Set Analog_Bridge digital mode"
    echo -e "\t tune tg \t\t\t\t\t Tune to specific TG/Reflector"
    echo -e "\t ambesize {72|88|49}\t\t\t\t Set number of bits for ambe data"
    echo -e "\t ambemode {DMR|NXDN|P25|YSFN|YSFW|DSTAR} \t Set AMBE mode"
    echo -e "\t slot {1|2} \t\t\t\t\t Set DMR slot to transmit on"
    echo -e "\t update \t\t\t\t\t Update callsign and host databases"
    echo -e "\t tlvAudio mode gain\t\t\t\t Set AMBE audio mode and gain"
    echo -e "\t usrpAudio mode gain\t\t\t\t Set PCM audio mode and gain"
    echo -e "\t usrpAgc threshold slope decay\t\t\t Set PCM audio agc threshold slope and decay"
    echo -e "\t usrpCodec {SLIN|ULAW|ADPCM}\t\t\t Set AB -> DVSM/UC audio codec"
    echo -e "\t tlvPorts rxport txport\t\t\t\t Set Analog_Bridge receive and transmit ports"
    echo -e "\t info \t\t\t\t\t\t Update ABInfo and send to DVSM/UC"
    echo -e "\t show \t\t\t\t\t\t Pretty print the ABInfo json file"
    echo -e "\t lookup \t\t\t\t\t Lookup a DMR ID/call in the local database"
    echo -e "\t mute {OFF|USRP|TLV|BOTH}\t\t\t Cause Aanlog_Bridge to mute a stream"
    echo -e "\t message msg\t\t\t\t\t Send a text message to DVSM/UC"
    echo -e "\t macro {file|text}\t\t\t\t Send a macro collection to DVSM"
    echo -e "\t pushfile file\t\t\t\t\t Push file to DVSM"
    echo -e "\t pushurl url\t\t\t\t\t Push URL to DVSM"
    echo -e "\t collectProcessDataFiles \t\t\t Collect and prepare DVSM data files"
    echo -e "\t collectProcessPushDataFiles \t\t\t Collect, prepare and upload DVSM data files"
    echo -e "\t collectProcessPushDataFilesHTTP \t\t Collect, prepare and upload DVSM data files over http"
    echo -e "\t reloadDatabase \t\t\t\t Tell AB to reload database files into memory"
    echo -e "\t getEnabledModes \t\t\t\t Return the list of "enabled" modes in MB.ini"
    echo -e "\t getUDPPortOwner {UDP port}\t\t\t Print out the process owner for the specified port"
    echo -e "\t getUDPPortsForProcess {process name|ALL}\t Print out the ports owned by the specified process (or all DVSwitch processes)"
    echo -e "\t updateINIFileValue file section {tag} {value}\t Display or edit a tag in an INI file"
    echo -e "\t gps lat long \t\t\t\t\t Set GPS coordinates for YSF to lat and long"
    echo -e "\t setGpsToIP \t\t\t\t\t Set GPS coordinates for YSF to the lat and long of your public IP address"
    exit 1
}

#################################################################
# The main application
#################################################################
if [ $# -eq 0 ]; then
    usage   # No arguments, so just report usage information
else
    case $1 in
        -h|--help|"-?"|help)
            usage
        ;;
        update)
            downloadDatabases
        ;;
        lookup)
            lookup $2
        ;;
        collectProcessDataFiles|collectprocessdatafiles|cpdf)
            collectProcessDataFiles
        ;;
        version|-v)
            appVersion $2
        ;;
        getEnabledModes|getenabledmodes|gem)
            if [ $# -eq 1 ]; then   # No argument passed, just return the current value 
                getEnabledModes "Enabled Modes: "
            else
                getEnabledModes "$2"
            fi
        ;;
        getUDPPortOwner|getudpportowner|gupo)
            getUDPPortOwner "$2"
        ;;
        getUDPPortsForProcess|getudpportsforprocess|gupfp)
            if [ -z "$2" ] || [ $2 == "all" ] || [ $2 == "ALL" ]; then
                getUDPPortsForDVSwitch
            else
                for i in "${@:1}"; do
                    getUDPPortsForProcess "$i"
                done
            fi
        ;;
        updateINIFileValue|updateinifilevalue|uifv)
            updateINIFileValue "$2" "$3" $4 $5 ${@:6}
        ;;
        parseIniFile|parseinifile|pif)
            parseAnyIniFile "$2" $3 $4
        ;;
        *)
            # All the commands below require that a valid ABInfo file exists.  
            TLV_PORT=`getTLVPort`   # Get the communications port to use before we go further
            USRP_PORT=`getUSRPPort`   # Get the communications port to use before we go further
            if [ $TLV_PORT == "ERROR" ]; then
                echo "Can not find /tmp/ABInfo file (have you run Analog_Bridge?), aborting" 
                exit 1
            fi
            case $1 in
                mode)
                    setMode $2 $3 $4
                ;;
                tune)
                    ${DEBUG} tune $2
                    ${DEBUG} getInfo
                ;;
                ambeSize|ambesize)
                    ${DEBUG} setAmbeSize $2
                ;;
                ambeMode|ambemode)
                    ${DEBUG} setAmbeMode $2
                ;;
                slot)
                    ${DEBUG} setSlot $2
                ;;
                setCallAndId|setcallandid)
                    setCallAndID $2 $3
                    getInfo
                ;;
                tlvAudio|tlvaudio)
                    setTLVAudioType $2
                    setTLVGain $3
                ;;
                usrpAudio|usrpaudio)
                    setUSRPAudioType $2
                    setUSRPGain $3
                ;;
                USRPAgc|usrpagc)
                    setUSRPAgc $2 $3 $4
                ;;
                TLVAgc|tlvagc)
                    setTLVAgc $2 $3 $4
                ;;
                usrpCodec|usrpcodec)
                    setUSRPCodec $2
                ;;
                tlvPorts|tlvports)
                    setTLVRxPort $2
                    setTLVTxPort $3
                ;;
                info)
                    # no arguments fill just tell AB to update the json file
                    # two arguments returns the value of "object" and "name" object{name:value}
                    getInfo $2 $3
                ;;
                show)
                    prettyPrintInfo
                ;;
                mute)
                    setMute $2
                ;;
                pushFile|pushfile|pf)
                    pushFileToClient "$2"
                ;;
                collectProcessPushDataFiles|collectprocesspushdatafiles|cppdf)
                    collectProcessPushDataFiles
                ;;
                pushUrl|pushurl)
                    pushURLToClient "$2"
                ;;
                collectProcessPushDataFilesHTTP|collectprocesspushdatafileshttp|cppdfh)
                    collectProcessPushDataFilesHTTP
                ;;
                reloadDatabase|reloaddatabase)
                    reloadDatabase
                ;;
                message)
                    sendMessage "$2"
                ;;
                macro)
                    sendMacro macro "$2"
                ;;
                menu)
                    sendMacro menu "$2"
                ;;
                ping)
                    setPingTimer "$2"
                ;;
                gps)
                    remoteControlCommand "gps=$2,$3"
                ;;
                exit)
                    remoteControlCommand "exit=0 0"
                ;;
                setGpsToIP)
                    setGpsToIP
                ;;
                exitAB|exitab)
                    exitAnalogBridge $2 $3
                ;;
                usrpCommand|usrp)   # undocumented ATM/WIP
                    USRPCommand "$2" "$3"
                ;;
                *)
                    # unknown option, update branch info (no option is specified, just ordered by placement)
                    echo "Unknown command line option:" $1
                    usage
                ;;
            esac
                ;;
    esac
fi
exit $_ERRORCODE