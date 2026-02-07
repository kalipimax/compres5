#!/bin/bash
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

BASE_DIR="$(pwd)"

get_input() {
    local prompt="$1"
    local default="$2"
    read -p "$prompt [$default]: " value
    echo "${value:-$default}"
}

MOB_VID=$(get_input "Mobile video compression mode (Y/N)" "N")

if [[ "${MOB_VID^^}" =~ ^(Y|YES)$ ]]; then
    MIN_SAVE=0
    TARGET_HEIGHT=1080
    TARGET_WIDTH=1920
    IGNORE_SMALL="YES"
    AUDIO_CH=2
    CRF=23
    SKIP_SAMPLE=1
else
    MIN_SAVE=$(get_input "Minimum percentage space saving" "10")
    TARGET_HEIGHT=$(get_input "Target vertical resolution" "1080")
    IGNORE_SMALL=$(get_input "Ignore files ≤${TARGET_HEIGHT}p (YES/NO)" "NO")
    AUDIO_CH=$(get_input "Audio channels (1=mono, 2=stereo)" "2")
    CRF=$(get_input "CRF value (17–28, lower = better quality)" "27")
    SKIP_SAMPLE=0
fi

AUDIO_OPTS=$([[ "$AUDIO_CH" == "1" ]] && echo "-ac 1" || echo "-ac 2")
TARGET_FRAMERATE="25"
LOGFILE="$BASE_DIR/compress_log_${TARGET_HEIGHT}.txt"

if [[ "$AUDIO_CH" == "1" ]]; then
    AUDIO_FILTER="pan=mono|c0=0.5*FL+0.5*FR+0.707*FC+0.5*BL+0.5*BR,loudnorm=I=-23:TP=-1.5:LRA=7"
else
    AUDIO_FILTER="pan=stereo|FL<FL+0.707*FC+0.707*BL|FR<FR+0.707*FC+0.707*BR,loudnorm=I=-23:TP=-1.5:LRA=7"
fi

test_sample() {
    local file="$1"
    local tmp_orig=$(mktemp --suffix=.mp4)
    local tmp_new=$(mktemp --suffix=.mp4)

    ffmpeg -nostdin -y -i "$file" -t 30 -c copy "$tmp_orig" >/dev/null 2>&1 || { rm -f "$tmp_orig" "$tmp_new"; echo "0"; return; }

    if [[ $SKIP_SAMPLE -eq 1 ]]; then
        rm -f "$tmp_orig" "$tmp_new"
        echo "100"
        return
    fi

    ffmpeg -nostdin -y -i "$file" -t 30 \
        -vf "scale='if(gt(ih,${TARGET_HEIGHT}),-2,iw)':'if(gt(ih,${TARGET_HEIGHT}),${TARGET_HEIGHT},ih)',setsar=1" \
        -r "${TARGET_FRAMERATE}" \
        -af "${AUDIO_FILTER}" \
        -c:v libx265 -crf ${CRF} -preset slow \
        -c:a aac -b:a 128k ${AUDIO_OPTS} \
        -threads 4 "$tmp_new" >/dev/null 2>&1 || { rm -f "$tmp_orig" "$tmp_new"; echo "0"; return; }

    local orig_size=$(stat -c%s "$tmp_orig" 2>/dev/null || echo "1")
    local new_size=$(stat -c%s "$tmp_new" 2>/dev/null || echo "1")
    rm -f "$tmp_orig" "$tmp_new"

    [[ $orig_size -eq 0 ]] && echo "0" || echo $(( (100 * (orig_size - new_size)) / orig_size ))
}

full_compress() {
    local file="$1"
    local out="$2"
    local width="$3"
    local height="$4"

    local scale_filter
    if [[ $SKIP_SAMPLE -eq 1 ]]; then
        if (( width > height )); then
            scale_filter="scale='if(gt(iw,${TARGET_WIDTH}),${TARGET_WIDTH},-2)':'if(gt(ih,${TARGET_HEIGHT}),${TARGET_HEIGHT},-2)',setsar=1"
        else
            scale_filter="scale='if(gt(iw,${TARGET_HEIGHT}),${TARGET_HEIGHT},-2)':'if(gt(ih,${TARGET_WIDTH}),${TARGET_WIDTH},-2)',setsar=1"
        fi
    else
        scale_filter="scale='if(gt(ih,${TARGET_HEIGHT}),-2,iw)':'if(gt(ih,${TARGET_HEIGHT}),${TARGET_HEIGHT},ih)',setsar=1"
    fi

    nice -n 19 ionice -c3 ffmpeg -nostdin -i "$file" \
        -vf "$scale_filter" \
        -r "${TARGET_FRAMERATE}" \
        -af "${AUDIO_FILTER}" \
        -c:v libx265 -crf ${CRF} -preset slow \
        -c:a aac -b:a 128k ${AUDIO_OPTS} \
        -movflags +faststart \
        -threads 0 \
        "$out" >/dev/null 2>&1
}

trap 'echo "ERR:$LINENO" >> "$LOGFILE"' ERR INT TERM

[[ ! -f "$LOGFILE" ]] && echo "CRF=${CRF}|AUDIO=${AUDIO_CH}ch|MOBILE=${MOB_VID}" > "$LOGFILE"

find . -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" \
    -o -iname "*.mpg" -o -iname "*.wmv" -o -iname "*.m4v" -o -iname "*.mts" \
    -o -iname "*.vob" -o -iname "*.rm" -o -iname "*.3gp" -o -iname "*.webm" \) \
    ! -path "*/COMPRESSED${TARGET_HEIGHT}/*" \
    -printf '%h\0' | sort -uz | while IFS= read -r -d '' DIR; do

    cd "$DIR" || continue

    OUT_DIR="COMPRESSED${TARGET_HEIGHT}"
    mkdir -p "$OUT_DIR"

    PROCESSED_FILES=$(awk -F'|' '{print $1}' "$LOGFILE" 2>/dev/null)

    find . -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" \
        -o -iname "*.mov" -o -iname "*.mpg" -o -iname "*.wmv" -o -iname "*.m4v" \
        -o -iname "*.mts" -o -iname "*.vob" -o -iname "*.rm" -o -iname "*.3gp" \
        -o -iname "*.webm" \) -print0 | while IFS= read -r -d '' FILE; do

        FILE="${FILE#./}"

        echo "$PROCESSED_FILES" | grep -qxF "$FILE" && continue

        WIDTH=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 "$FILE" 2>/dev/null)
        HEIGHT=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$FILE" 2>/dev/null)

        if [[ -z "$HEIGHT" ]] || [[ ! "$HEIGHT" =~ ^[0-9]+$ ]] || [[ -z "$WIDTH" ]] || [[ ! "$WIDTH" =~ ^[0-9]+$ ]]; then
            echo "$FILE|ERR" >> "$LOGFILE"
            continue
        fi

        if [[ $SKIP_SAMPLE -eq 1 ]]; then
            if (( WIDTH > HEIGHT )); then
                if (( WIDTH <= TARGET_WIDTH && HEIGHT <= TARGET_HEIGHT )); then
                    echo "$FILE|SKIP" >> "$LOGFILE"
                    continue
                fi
            else
                if (( WIDTH <= TARGET_HEIGHT && HEIGHT <= TARGET_WIDTH )); then
                    echo "$FILE|SKIP" >> "$LOGFILE"
                    continue
                fi
            fi
        else
            if [[ "${IGNORE_SMALL^^}" =~ ^(YES)$ ]] && (( HEIGHT <= TARGET_HEIGHT )); then
                echo "$FILE|SKIP" >> "$LOGFILE"
                continue
            fi
        fi

        BASENAME="${FILE%.*}"
        OUTPUT_FILE="$OUT_DIR/${BASENAME}.mp4"

        [[ -f "$OUTPUT_FILE" ]] && { echo "$FILE|SKIP" >> "$LOGFILE"; continue; }

        EXT_LOWER=$(echo "${FILE##*.}" | tr '[:upper:]' '[:lower:]')

        if [[ "$EXT_LOWER" == "mp4" ]] && [[ $SKIP_SAMPLE -eq 0 ]]; then
            SAVE=$(test_sample "$FILE")
            (( SAVE < MIN_SAVE )) && { echo "$FILE|SKIP|${SAVE}%" >> "$LOGFILE"; continue; }
        fi

        full_compress "$FILE" "$OUTPUT_FILE" "$WIDTH" "$HEIGHT"

        if [[ ! -s "$OUTPUT_FILE" ]]; then
            echo "$FILE|ERR" >> "$LOGFILE"
            rm -f "$OUTPUT_FILE"
            continue
        fi

        SIZE_ORIG=$(stat -c%s "$FILE")
        SIZE_NEW=$(stat -c%s "$OUTPUT_FILE")
        FINAL_SAVE=$(( (100 * (SIZE_ORIG - SIZE_NEW)) / SIZE_ORIG ))

        echo "$FILE|OK|${FINAL_SAVE}%" >> "$LOGFILE"
    done

    cd "$BASE_DIR" || exit
done

echo "END:$(date +%s)" >> "$LOGFILE"
