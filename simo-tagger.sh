#!/bin/sh
# Simo.sh
# pX <xaccrocheur@gmail.com>
# Time-stamp: <2011-05-27 20:40:25>
# ===================================================================

Simo=`which $0`
scriptName=$(basename $0)
version="0.0.5"

artistTagChecked=false
albumTagChecked=false
yearTagChecked=false
trackTagChecked=false
genreTagChecked=false
commentTagChecked=false
organizationTagChecked=false
silent=false
signature=false

# Check arguments given
while getopts ":hcsdbkf:" optname
    do
        case "$optname" in
            "h")
                echo -e "Simo (Semi-Intelligent Media Ordinator)\n  will read your music files, encode them to ogg/vorbis, reading every tag,\n  and attempt to guess missing ones, prompting you otherwise.\n"
                echo -e "Usage:\n  $scriptName [ OPTIONS... ]\n"
                echo -e "Options\n  -h\t\t\t\tDisplay this help\n  -d <dir>\t\t\tStart processing <dir>\n  -c\t\t\t\tCommand line mode (no GUI)\n  -b\t\t\t\tSet encoding bit rate (64k, 128k, 256k, 512k)\n  -k\t\t\t\tKey: Your private key to sign audio files\n  -s\t\t\t\tSilent: Auto-accept proposed values\n"
                exit 0;
            ;;
            "c")
                zen=false
            ;;
            "s")
                silent=true
            ;;
            "d")
            workingDir=${OPTARG}
            ;;
            "b")
            bitRate=${OPTARG,,*}
            ;;
            "k")
            privKey=${OPTARG}
	    signature=true
            ;;
            "f")
            myRealFile=${OPTARG}
	    oneFile=true
            ;;
            "?")
            echo "Unknown option $OPTARG"
            exit 1
            ;;
            ":")
            echo "No argument value for option $OPTARG"
            exit 1
            ;;
            *)
            # Should not occur
            echo "Unknown error while processing options"
            exit 1
            ;;
        esac
    done

# Verify that the right commands are installed
type -P zenity &>/dev/null || { zen=false >&2; }
type -P exiftool &>/dev/null || { isExif=false >&2; }
type -P ffmpeg &>/dev/null || { isFfmpeg=false >&2; }
type -P vorbiscomment &>/dev/null || { isVcomment=false >&2; }
type -P kdialog &>/dev/null || { isKde=false >&2; }

if ! $isExif || ! $isFfmpeg || ! $isVcomment ; then
    somethingsMissing=true
else
    somethingsMissing=false
fi

if $somethingsMissing ; then
    if $zen ; then
        zenity --info --title="$scriptName $version" --text="Please install :\n<b><a href='http://www.ffmpeg.org/'>ffmpeg</a> \n<a href='http://www.sno.phy.queensu.ca/~phil/exiftool/'>exiftool</a> \n<a href='http://wiki.xiph.org/VorbisComment'>vorbiscomment</a></b> \nand restart ${scriptName}"
    else
        echo "####### Please install : exiftool ffmpeg vorbiscomment"
    fi
    exit 1;
fi

isnumber() {
  if expr match "$1" "\($regexp\)" &> /dev/null ; then
    return 0
  else
    return 1
  fi
}

# Trap errors
function errors() {
    if $zen ; then
        restart=$(zenity --question --title="$scriptName $version" --text="Something went wrong. Do you want to quit or restart $scriptName ?" --cancel-label="Quit" --ok-label="Restart")
        if [ "$?" == "0" ] ; then
            $Simo;
        else
            exit 0;
        fi
    fi
}

trap errors ERR;

echo -e "####### Welcome to Simo, the Semi-Intelligent Music Organizer\n
  ($scriptName -h for help)\n
  Show me to your audio files, and I'll encode them - preserving the tags.
  If I really can't figure something out, I'll ask you.
  But I'll remember your answer(s).
  Sounds good? Well you know what us musicians say : Then it IS good.
  And one, two, three, four!\n"

# Select working dir
if [[ $workingDir == "" ]] ; then
    workingDir=$( pwd );
    if $zen ; then
        echo "####### $scriptName $version X-Window mode - use -c for command-line interface, -h for help"
        workingDir=$(zenity --file-selection --directory --filename=${workingDir##*/}"/" --title="$scriptName $version - Where are the audio files to convert? Select a directory")
    else
        echo -e "####### $scriptName $version console mode - consider installing zenity\n"
    fi
fi

if ! $signature ; then
    if $zen ; then
        privKey=$(zenity --file-selection --title="$scriptName $version - Do you want to sign those files? Select private key file")
        case $? in
            0)
	        signature=true
	        ;;
            1)
	        signature=false
	        ;;
            -1)
	        signature=false
	        ;;
        esac
    else
        read -e -p "####### Do you want to sign those files? Select private key file > " privKey
    fi
fi


if $signature ; then

    if $zen ; then
	passPhrase=$(zenity --entry --hide-text --title="Passphrase of this key" --text="Enter the passphrase of this key")
    else
        echo "####### Enter the passphrase of this key "
        read -s -e passPhrase
    fi

    TMPFILE=$(mktemp ./tmp.XXXXXXXXXX) || exit 1
    echo $passPhrase > $TMPFILE
    
    privKeyPath="$privKey"
    pubkey=`openssl rsa -in $privKeyPath -pubout -passin file:$TMPFILE > pubkey.rsa`
    pubKey=`cat pubkey.rsa`
    pubKeyPath="pubkey.rsa"
    trap "rm -rf $TMPFILE" EXIT
else
    echo -e "####### No public key selected\n"
fi


# workingDir=${workingDir##*/}

numberOfWavFiles=$(ls -la "${workingDir}"/*.wav 2>/dev/null | wc -l)
numberOfMp3Files=$(ls -la "${workingDir}"/*.mp3 2>/dev/null | wc -l)
numberOfFlacFiles=$(ls -la "${workingDir}"/*.flac 2>/dev/null | wc -l)
numberOfFiles=$(( $numberOfWavFiles + $numberOfMp3Files + $numberOfFlacFiles ))
mydirName=${workingDir##*/}
# declare -A thisAlbumTags

if [ $numberOfFiles -eq 0 ] ; then
  echo "####### Found no audio files in this directory. Aborting."
  exit
fi

if $zen ; then
        yn=`zenity --question --title="$scriptName $version" --text="Convert $numberOfFiles audio files to ogg/vorbis, with tags ?"`
    else
        read -e -p "####### Convert $numberOfFiles audio files to ogg/vorbis, with tags ? [Y/n] " yn
fi

# Select bitrate
if [[ $yn == "y" || $yn == "Y" || $yn == "" ]] ; then

if [[ $bitRate != "" ]] ; then
    mybitRate=$bitRate
else
    if $zen ; then
        bitRate=`zenity --title "Select a bitrate" --text "Files encoding bitrate" --width=150 --height=230 --list --radiolist --column "Selected" --column "Bitrate" True 64k False 128k False 256k False 512k`
    else
        PS3="####### Select a bitrate > "
        select mybitrate in 64k 128k 256k 512k
        do
            if [[ -n $mybitrate ]]; then
                bitRate=$mybitrate
                echo -e "####### Bitrate is " ${bitRate} "###"
                break
            else
                echo "####### Must choose a bitrate, now come on"
            fi
        done
    fi
fi
else
    exit
fi

# Process files
shopt -s nullglob
fileNumber=0
for infile in "${workingDir}"/*.wav "${workingDir}"/*.mp3 "${workingDir}"/*.flac
do
    fileNumber=$(($fileNumber+1))
    infileExt=${infile#*.}
    infileExt=${infileExt#*.}
    infileExt=${infileExt#*.}
    infileName=${infile%.*}
    fullFilePath="${infileName}.${infileExt}"
    fullFileName=$(basename "${fullFilePath}")
    realFileName=${fullFileName%.*}
    fullFilePathNoExt=${fullFilePath%.*}
    TAG_title=$(exiftool -Title "${fullFilePath}" | sed 's/.*://g;s/^[ \t]*//')
    TAG_artist=$(exiftool -Artist "${fullFilePath}" | sed 's/.*://g;s/^[ \t]*//')
    TAG_album=$(exiftool -Album "${fullFilePath}" | sed 's/.*://g;s/^[ \t]*//')
    TAG_year=$(exiftool -Year "${fullFilePath}" | sed 's/.*://g;s/^[ \t]*//')
    TAG_track=$(exiftool -Track "${fullFilePath}" | sed 's/.*://g;s/^[ \t]*//')
    TAG_genre=$(exiftool -Genre "${fullFilePath}" | sed 's/.*://g;s/^[ \t]*//')
    TAG_comment=$(exiftool -Comment "${fullFilePath}" | sed 's/.*://g;s/^[ \t]*//')
    TAG_organization=$(exiftool -ORGANIZATION "${fullFilePath}" | sed 's/.*://g;s/^[ \t]*//')

    if $zen ; then
        echo -e "####### Reading" file "number ${fileNumber} : ${realFileName}" "###"
    else
        echo -e "####### Reading" file "number ${fileNumber} : ${realFileName}" "###"
    fi

    if [[ $TAG_title == "empty" || $TAG_title == "None"  || $TAG_title == " " || $TAG_title == Track*  || $TAG_title == track* ]] ; then
        TAG_title=
    fi

    if [[ $TAG_title != "" ]] ; then
        titleTag=$TAG_title
    else
    suggestTitleName=$(echo ${realFileName} | sed -e 's/[-_]/ /g' | sed -e 's/\([0-9]\)//g')
    upperCase=( $suggestTitleName )
    suggestTitleName="${upperCase[@]^}"
        if ! $silent ; then
            if $zen ; then
                titleTag=$(zenity --title="Enter track title" --entry --text "Title of this track (${suggestTitleName})?" --entry-text="")
            else
                read -e -p "####### \"Title\" tag ? > " -i "$suggestTitleName" titleTag
            fi
        else
            titleTag=${suggestTitleName}
        fi
    fi

    if [ $TAG_track -eq $TAG_track 2> /dev/null ] ; then
        :
    else
        TAG_track=
    fi

    if [[ $TAG_track == "" ]] ; then
        trackNumberInFileName=$(echo ${realFileName} | sed -e '/^.*\(.\)\([0-9][0-9]\)\1.*$/!d;s//\2/')
        if [[ $trackNumberInFileName != "" ]] ; then
            suggestTrack=${trackNumberInFileName}
        else
            suggestTrack=${fileNumber}
        fi

        if ! $silent ; then
            if $zen ; then
                trackTag=$(zenity --entry --title="Enter track #" --text="Track number for ${realFileName}?" --entry-text="$suggestTrack")
            else
                read -e -p "####### \"Track number\" tag ? > " -i "$suggestTrack" trackTag
            fi
        else
            trackTag=${suggestTrack}
        fi
        
    else
        trackTag=$TAG_track
    fi

    if [[ $TAG_artist == "empty" || $TAG_artist == "None"  || $TAG_artist == "NoArtist" || $TAG_artist == " " ]] ; then
        TAG_artist=
    fi

    if [[ $TAG_artist != "" ]] ; then
        artistTag=$TAG_artist
    else
        suggestArtistName=$(echo ${realFileName} | sed 's/_/\ /g')

        if ! $silent ; then
            if ! $artistTagChecked ; then
                if $zen ; then
                    artistTag=$(zenity --entry --title="Enter artist name" --text="Artist name (${realFileName})?" --entry-text="${suggestArtistName}")
                else
                    read -e -p "####### \"Artist\" tag ? > " -i "${suggestArtistName}" artistTag
                fi
                artistTagChecked=true
            fi
        else
            artistTag=${suggestArtistName}
        fi
    fi

    if [[ $TAG_album == "empty" || $TAG_album == "None"  || $TAG_album == "Unknown CD" || $TAG_album == " " ]] ; then
        TAG_album=
    fi

    if [[ $TAG_album != "" ]] ; then
        albumTag=$TAG_album
    else
        if ! $silent ; then
            if ! $albumTagChecked ; then
                if $zen ; then
                    albumTag=$(zenity --entry --title="Enter album name" --text="Album name (${realFileName})?" --entry-text="${mydirName}")
                else
                    read -e -p "####### \"Album\" tag ? > " -i "${mydirName}" albumTag
                fi
                albumTagChecked=true
            fi
        else
            albumTag=${mydirName}
        fi
    fi

    if [ $TAG_year -eq $TAG_year 2> /dev/null ] ; then
        :
    else
        TAG_year=
    fi

    if [[ $TAG_year != "" ]] ; then
        yearTag=$TAG_year
    else
        suggestYear=$(echo ${mydirName} | sed -e '/^.*\(.\)\([0-9][0-9][0-9][0-9]\)\1.*$/!d;s//\2/')
        if [[ $suggestYear == "" ]] ; then
            suggestYear=$(echo ${realFileName} | sed -e '/^.*\(.\)\([0-9][0-9][0-9][0-9]\)\1.*$/!d;s//\2/')
        fi
        if ! $silent ; then
            if ! $yearTagChecked ; then
                if $zen ; then
                    yearTag=$(zenity --entry --title="Enter year" --text="Year (${realFileName})?" --entry-text="${suggestYear}")
                else
                    read -e -p "####### \"Year\" tag ? > " -i "$suggestYear" yearTag
                fi
                yearTagChecked=true
            fi
        else
            yearTag=${suggestYear}
        fi
    fi

    if [[ $TAG_genre == "empty" || $TAG_genre == "None"  || $TAG_genre == "Unknown CD" || $TAG_genre == " " ]] ; then
        TAG_genre=
    fi

    if [[ $TAG_genre != "" ]] ; then
        genreTag=$TAG_genre
    else
        if ! $silent ; then
            if ! $genreTagChecked ; then
                if $zen ; then
                    genreTag=$(zenity --entry --title="Enter genre" --text="Genre (${realFileName})?" --entry-text="")
                else
                    read -e -p "####### \"Genre\" tag ? > " genreTag
                fi
                genreTagChecked=true
            fi
        else
            genreTag=
        fi
    fi

    if [[ $TAG_comment == "empty" || $TAG_comment == "None" || $TAG_comment == " " ]] ; then
        TAG_comment=
    fi

    if [[ $TAG_comment != "" ]] ; then
        commentTag=$TAG_comment
    else
        if ! $silent ; then
            if ! $commentTagChecked ; then
                if $zen ; then
                    commentTag=$(zenity --entry --title="Enter comment" --text="Any comment about (${realFileName})?" --entry-text="")
                else
                    read -e -p "####### \"Comment\" tag ? > " commentTag
                fi
                commentTagChecked=true
            fi
        else
            commentTag=
        fi
    fi

    if [[ $TAG_organization == "empty" || $TAG_organization == "None" || $TAG_organization == " " ]] ; then
        TAG_organization=
    fi

    if [[ $TAG_organization != "" ]] ; then
        organizationTag=$TAG_organization
#             thisAlbumTags["organization"]=$TAG_organization
    else
        if ! $silent ; then
            if ! $organizationTagChecked ; then
                if $zen ; then
                    organizationTag=$(zenity --entry --title="Enter record label name" --text "Organization (Record label) of (${realFileName})?" --entry-text "")
                else
                    read -e -p "####### \"Organization\" (Record label) tag ? > " organizationTag
                fi
                organizationTagChecked=true
            fi
        else
            organizationTag=
        fi
    fi

    encodeCommand=$(ffmpeg -loglevel quiet -v 1 -y -i "${fullFilePath}" -metadata title="${titleTag}" -acodec libvorbis -ab ${bitRate} "${fullFilePathNoExt}.ogg")

    echo "##################### TMPFILE :"$TMPFILE

    if $signature ; then
	echo "@@@@@@@@@@@@@@@@@@@ privKeyPath is $privKeyPath"
	retagCommand=$(vorbiscomment -w "$infileName.ogg" -t "ARTIST=${artistTag}" -t "TITLE=${titleTag}" -t "ALBUM=$albumTag" -t "YEAR=$yearTag" -t "TRACK=$trackTag" -t "GENRE=$genreTag" -t "COMMENT=$commentTag" -t "ORGANIZATION=$organizationTag" -t "PUBKEY=$pubKey") && openssl dgst -sha1 -sign "$privKeyPath" -out "$infileName.ogg".sha1  "$infileName.ogg"

#openssl dgst -sha1 -sign ../../AZERO/Azer0-key.pem -out Azer0-400-02-GateCrashers.ogg.sha1 Azer0-400-02-GateCrashers.ogg


#binaryHash=$(uuencode "$infileName.ogg".sha1)

# -passin pass:$TMPFILE 
#        7z a ${infileName}.7z ${infileName}.ogg ${infileName}.ogg.sha1 pubkey.rsa
#        rm pubkey.rsa ${infileName}.ogg.sha1
    echo "##################### TMPFILE :"$TMPFILE
    else
	retagCommand=$(vorbiscomment -w "$infileName.ogg" -t "ARTIST=${artistTag}" -t "TITLE=${titleTag}" -t "ALBUM=$albumTag" -t "YEAR=$yearTag" -t "TRACK=$trackTag" -t "GENRE=$genreTag" -t "COMMENT=$commentTag" -t "ORGANIZATION=$organizationTag")
    fi

    if $zen ; then
        ${encodeCommand} 2>&1 | zenity --progress --text="Converting: <b>${realFileName}</b> to <b>Ogg/Vorbis</b> at <b>${bitRate}b/s</b>" --title="$scriptName $version - Encoding" --auto-close --auto-kill --pulsate
        ${retagCommand} 2>&1 | zenity --progress --text="Converting: <b>${realFileName}</b> to <b>Ogg/Vorbis</b> at <b>${BITRATE}</b> kb/s" --title="$scriptName $version - Tagging" --auto-close --pulsate
    else
        ${encodeCommand}
        ${retagCommand}
    fi

    myMessage="####### ${realFileName}.ogg\n
Title\t\t${titleTag}\n
Artist\t\t${artistTag}\n
Album\t\t${albumTag}\n
Year\t\t${yearTag}\n
Track\t\t${trackTag}\n
Genre\t\t${genreTag}\n
Record Label\t${organizationTag}\n
Comment\t${commentTag}\n
Public Key\t${pubKey}\n"
    
    echo -e "\n##########################################"
    echo -e ${myMessage}
    echo -e "##########################################\n"
done

if $isKde ; then
kdialog --title "$scriptName $version" --passivepopup "Finished proper encoding of $numberOfFiles audio files" 10
fi

if $zen ; then
    zenity --notification --window-icon="info" --text="$scriptName $version finished proper encoding of $numberOfFiles audio files"
fi

echo -e "####### Finished proper encoding of $numberOfFiles audio files"
echo -e "####### $scriptName $version - BBye !"