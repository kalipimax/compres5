# Compres5

**Local video compresor for video files**


## Features

### Mobile mode.
Reducing size of the video to 1080x1920, compressing  with H265 at CRF=23

### Normal mode.
 You can chose :
- minimum estimated space saving
- max target resolution
- ignore files smaller than target resolution (chose N if your priority is a space saving)
- Audio MONO/STEREO
- CRF level (27 makes ugly squares in dark scenes, good enough for archiving YouTube videos, 23 for films)

## Work

Scrypt will work in the folder, is located and ALL subfolders. 
It will NOT delete any files, it will make new COMPRESSED folder in every subfolder, where video files are found.
Do not delete original videos until you checked, that compresed file is of good quality and has same lenght.
When you terminate the script, check for unfinished jobs in COMPRESSED folders.

The authors accept no responsibility for misuse or data loss.
Free to use and modify as you wish.