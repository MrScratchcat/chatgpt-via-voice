#!/bin/bash

# Function to check if a command exists
command_exists() {
    type "$1" &> /dev/null ;
}

# Function to check if a package is installed
package_installed() {
    dpkg -l | grep "^ii" | grep -q "$1"
}

# Function to install a package
install_package() {
    echo "Installing $1..."
    sudo apt-get update && sudo apt-get install -y $1
}

# Commands and their corresponding package names if different
declare -A required_software=( ["curl"]="curl" ["jq"]="jq" ["sox"]="sox" )

# Check each command and install if necessary
for cmd in "${!required_software[@]}"; do
    if command_exists "$cmd"; then
        echo "$cmd is installed."
    else
        echo "$cmd is not installed."
        install_package "${required_software[$cmd]}"
    fi
done

# Special case for libsox-fmt-mp3, checking package installation
if package_installed "libsox-fmt-mp3"; then
    echo "libsox-fmt-mp3 is installed."
else
    echo "libsox-fmt-mp3 is not installed."
    install_package "libsox-fmt-mp3"
fi

# Check for gnome-terminal
if command_exists "gnome-terminal"; then
    echo "gnome-terminal is installed."
else
    echo "gnome-terminal is not installed."
    install_package "gnome-terminal"
fi

API_KEY_FILE="OPENAI_API_KEY"
API_URL="https://api.openai.com/v1/models"

# Function to check API key validity
function check_api_key() {
    local test_response=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $1" "$API_URL")

    if [ "$test_response" -eq 200 ]; then
        echo "API key is valid."
        return 0
    else
        echo "API key is invalid or failed to authenticate."
        return 1
    fi
}

# Attempt to load API key from file; prompt for a new one if invalid or not found
if [ ! -f "$API_KEY_FILE" ] || [ ! -s "$API_KEY_FILE" ]; then
    echo "OpenAI API key not found or file is empty."
else
    OPENAI_API_KEY=$(cat "$API_KEY_FILE")
    if check_api_key "$OPENAI_API_KEY"; then
        echo "Using API key from $API_KEY_FILE."
    else
        echo "The API key in $API_KEY_FILE is invalid."
    fi
fi

# If the API key is invalid or not found, prompt for a new one
if [ -z "$OPENAI_API_KEY" ] || ! check_api_key "$OPENAI_API_KEY"; then
    while true; do
        read -p "Please insert a new OpenAI API key: " OPENAI_API_KEY
        if check_api_key "$OPENAI_API_KEY"; then
            echo "$OPENAI_API_KEY" > "$API_KEY_FILE"
            echo "New API key saved to $API_KEY_FILE."
            break
        else
            echo "The API key provided is invalid. Please try again."
        fi
    done
fi

if [ ! -f "./loading.mp3" ]; then
    echo "The file 'loading.mp3' is not present. Making file"
    
    curl https://api.openai.com/v1/audio/speech \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
        "model": "tts-1",
        "input": "please wait for your response",
        "voice": "onyx"
    }' \
  --output loading.mp3
else
    echo "File is here nothing to do." 
fi


# Function to record until silence is detected
record_until_silence() {
    echo "Please start speaking..."
    sox -d recorded_audio.wav silence 1 0.1 1% 1 2.0 1%  
    echo "Recording stopped."
}

# Placeholder for transcribe_voice function
function transcribe_voice() {
    echo "Transcribing..."
    TRANSCRIPTION_RESPONSE=$(curl -s -X POST "https://api.openai.com/v1/audio/transcriptions" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -H "Content-Type: multipart/form-data" \
        -F file=@recorded_audio.wav \
        -F model="whisper-1")
    
    TRANSCRIBED_TEXT=$(echo $TRANSCRIPTION_RESPONSE | jq -r '.text')
    echo "Transcribed Text: $TRANSCRIBED_TEXT"
}

# Placeholder for chat_with_gpt function
function chat_with_gpt() {
    local input=$1

    RESPONSE=$(curl -s -X POST "https://api.openai.com/v1/chat/completions" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -H "Content-Type: application/json" \
        --data '{
            "model": "gpt-3.5-turbo",
            "messages": [
                {"role": "user", "content": "'"${input}"'"}
            ]
        }' | jq -r '.choices[0].message.content')

    echo "ChatGPT: $RESPONSE"
}

# convert_text_to_speech function
function convert_text_to_speech() {
    local text=$1
    local chunk_size=1000  
    local split_regex=".{$chunk_size}"
    local parts=($(echo $text | grep -oE $split_regex))
    
    local concatenated_length=0
    for part in "${parts[@]}"; do
        let concatenated_length+=${#part}
    done

    if [ $concatenated_length -lt ${#text} ]; then
        local last_chunk_start=$concatenated_length
        local last_chunk=${text:$last_chunk_start}
        parts+=("$last_chunk")
    fi

    for part in "${parts[@]}"; do
        echo "Processing part of the response..."
        curl -s -X POST "https://api.openai.com/v1/audio/speech" \
            -H "Authorization: Bearer $OPENAI_API_KEY" \
            -H "Content-Type: application/json" \
            -d '{
                "model": "tts-1",
                "input": "'"${part}"'",
                "voice": "onyx"
            }' --output response_audio.mp3

        gnome-terminal -- bash -c "play response_audio.mp3"
    done
}
# Main interaction loop
while true; do
    record_until_silence
    if [ -s recorded_audio.wav ]; then
        echo "Processing your voice input..."
        gnome-terminal -- bash -c "play loading.mp3"
        transcribe_voice
        
        if [ -n "$TRANSCRIBED_TEXT" ] && [ "$TRANSCRIBED_TEXT" != "null" ]; then
            chat_with_gpt "$TRANSCRIBED_TEXT"
            if [ -n "$RESPONSE" ] && [ "$RESPONSE" != "null" ]; then
                convert_text_to_speech "$RESPONSE"
            else
                echo "ChatGPT provided no response or unable to process."
            fi
        else
            echo "Could not transcribe voice, please try again."
        fi
    else
        echo "No voice detected, please try speaking again."
    fi

    CONTINUE=yes
    # read -p "Continue? (yes/no): " CONTINUE
    if [[ "$CONTINUE" != "yes" ]]; then
        echo "Exiting..."
        break
    fi
done