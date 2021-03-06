#!/bin/bash -x

### Global variables ###
RESOLUTION=${RESOLUTION:-1920x1080}
WIDTH="$(cut -d'x' -f1 <<< $RESOLUTION)"
HEIGHT="$(cut -d'x' -f2 <<< $RESOLUTION)"
export RESOLUTION
export WIDTH
export HEIGHT

# QUICK_START_ACTION indicates wich action to perform when COMPOSED_QUICK_START mode is executed
# Possible values are:
#   - Without parameters: Just execute all necessary configuration for xfvb and start chrome, waiting forever with a session openned
#   - --start-recording: Executes ffmpeg to record a session but don't stop chrome
#   - --stop-recording: Stops ffmpeg recording
COMPOSED_QUICK_START_ACTION=$1
export COMPOSED_QUICK_START_ACTION

if [[ -z "${COMPOSED_QUICK_START_ACTION}" ]]; then
    
    ### Variables ###
    URL=${URL:-https://www.youtube.com/watch?v=JMuzlEQz3uo}
    export URL

    ### Get a free display identificator ###

    DISPLAY_NUM=99
    DONE="no"

    while [ "$DONE" == "no" ]
    do
    out=$(xdpyinfo -display :$DISPLAY_NUM 2>&1)
    if [[ "$out" == name* ]] || [[ "$out" == Invalid* ]]
    then
        # Command succeeded; or failed with access error;  display exists
        (( DISPLAY_NUM+=1 ))
    else
        # Display doesn't exist
        DONE="yes"
    fi
    done
    
    export DISPLAY_NUM
    # Save DISPLAY_NUM in a temp file to be accessible for other scripts
    echo "export DISPLAY_NUM=${DISPLAY_NUM}" >> /tmp/DISPLAY_NUM

    echo "First available display -> :$DISPLAY_NUM"
    echo "----------------------------------------"

    pulseaudio -D

    ### Start Chrome in headless mode with xvfb, using the display num previously obtained ###

    touch xvfb.log
    chmod 777 xvfb.log
    xvfb-run --server-num=${DISPLAY_NUM} --server-args="-ac -screen 0 ${RESOLUTION}x24 -noreset" google-chrome --kiosk --start-maximized --test-type --no-sandbox --disable-infobars --disable-gpu --disable-popup-blocking --window-size=$WIDTH,$HEIGHT --window-position=0,0 --no-first-run --ignore-certificate-errors --autoplay-policy=no-user-gesture-required $URL &> xvfb.log &
    chmod 777 /recordings
    sleep infinity
    
elif [[ "${COMPOSED_QUICK_START_ACTION}" == "--start-recording" ]]; then

    source /tmp/DISPLAY_NUM
    
    # Remove possible stop file from previous recordings
    [ -e stop ] && rm stop
    # Create stop file
    touch stop

    # Variables
    ONLY_VIDEO=${ONLY_VIDEO:-false}
    FRAMERATE=${FRAMERATE:-25}
    VIDEO_ID=${VIDEO_ID:-video}
    VIDEO_NAME=${VIDEO_NAME:-video}
    VIDEO_FORMAT=${VIDEO_FORMAT:-mp4}
    RECORDING_JSON="${RECORDING_JSON}"
    
    export ONLY_VIDEO
    export FRAMERATE
    export VIDEO_ID
    export VIDEO_NAME
    export VIDEO_FORMAT
    export RECORDING_JSON
    
    ### Store Recording json data ###

    mkdir /recordings/$VIDEO_ID
    chmod 777 /recordings/$VIDEO_ID
    echo $RECORDING_JSON > /recordings/$VIDEO_ID/.recording.$VIDEO_ID
    
    ### Start recording with ffmpeg ###

    if [[ "$ONLY_VIDEO" == true ]]
    then
        # Do not record audio
        <./stop ffmpeg -y -f x11grab -draw_mouse 0 -framerate $FRAMERATE -video_size $RESOLUTION -i :$DISPLAY_NUM -c:v libx264 -preset ultrafast -crf 28 -refs 4 -qmin 4 -pix_fmt yuv420p -filter:v fps=$FRAMERATE "/recordings/$VIDEO_ID/$VIDEO_NAME.$VIDEO_FORMAT"
    else
        # Record audio  ("-f alsa -i pulse [...] -c:a aac")
        <./stop ffmpeg -y -f alsa -i pulse -f x11grab -draw_mouse 0 -framerate $FRAMERATE -video_size $RESOLUTION -i :$DISPLAY_NUM -c:a aac -c:v libx264 -preset ultrafast -crf 28 -refs 4 -qmin 4 -pix_fmt yuv420p -filter:v fps=$FRAMERATE "/recordings/$VIDEO_ID/$VIDEO_NAME.$VIDEO_FORMAT"
    fi

    ### Generate video report file ###
    ffprobe -v quiet -print_format json -show_format -show_streams /recordings/$VIDEO_ID/$VIDEO_NAME.$VIDEO_FORMAT > /recordings/$VIDEO_ID/$VIDEO_ID.info

    ### Update Recording json data ###

    TMP=$(mktemp /recordings/$VIDEO_ID/.$VIDEO_ID.XXXXXXXXXXXXXXXXXXXXXXX.json)
    INFO=$(cat /recordings/$VIDEO_ID/$VIDEO_ID.info | jq '.')
    HAS_AUDIO_AUX=$(echo $INFO | jq '.streams[] | select(.codec_type == "audio")')
    if [ -z "$HAS_AUDIO_AUX" ]; then HAS_AUDIO=false; else HAS_AUDIO=true; fi
    HAS_VIDEO_AUX=$(echo $INFO | jq '.streams[] | select(.codec_type == "video")')
    if [ -z "$HAS_VIDEO_AUX" ]; then HAS_VIDEO=false; else HAS_VIDEO=true; fi
    SIZE=$(echo $INFO | jq '.format.size | tonumber')
    DURATION=$(echo $INFO | jq '.format.duration | tonumber')

    if [[ "$HAS_AUDIO" == false && "$HAS_VIDEO" == false ]]
    then
        STATUS="failed"
    else
        STATUS="stopped"
    fi

    jq -c -r ".hasAudio=$HAS_AUDIO | .hasVideo=$HAS_VIDEO | .duration=$DURATION | .size=$SIZE | .status=\"$STATUS\"" "/recordings/$VIDEO_ID/.recording.$VIDEO_ID" > $TMP && mv $TMP /recordings/$VIDEO_ID/.recording.$VIDEO_ID

    ### Generate video thumbnail ###

    MIDDLE_TIME=$(ffmpeg -i /recordings/$VIDEO_ID/$VIDEO_NAME.$VIDEO_FORMAT 2>&1 | grep Duration | awk '{print $2}' | tr -d , | awk -F ':' '{print ($3+$2*60+$1*3600)/2}')
    THUMBNAIL_HEIGHT=$((480*$HEIGHT/$WIDTH))
    ffmpeg -ss $MIDDLE_TIME -i /recordings/$VIDEO_ID/$VIDEO_NAME.$VIDEO_FORMAT -vframes 1 -s 480x$THUMBNAIL_HEIGHT /recordings/$VIDEO_ID/$VIDEO_ID.jpg

    ### Change permissions to all generated files ###

    sudo chmod -R 777 /recordings/$VIDEO_ID

elif [[ "${COMPOSED_QUICK_START_ACTION}" == "--stop-recording" ]]; then
    
    echo 'q' > stop

fi



