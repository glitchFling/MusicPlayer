MusicPlayer A2:
.sprst Files:
A .sprst file is a Super Preset that stores not just your speed/reverb values, but your songs too!

Your songs will appear in On My iPhone/MusicPlayer/Library.

Your Super Preset will appear in On My iPhone/MusicPlayer/Super Presets.

In case you delete the app, make sure you back up your .sprst and .prst files.

iOS Shortcuts:
We are adding shortcut compatibility to MusicPlayer.

“Play Song” [FILE] - what it does is you select an audio file and it adds that song into your current session if it isn’t already stored.

“Clear All Songs” - it will clear all your songs. First, it will give a warning:

“This will Clear all your songs in the Session, are you sure you want to Clear all songs?”

[YES] [NO]

If you click yes, all songs in the playlist will be cleared. Simple as that.

Libs:
We are adding Libs into MusicPlayer!

DeBlytes: 
DeBlytes is an Audio Optimizer that partially uploads large audios so you can save GPU and Power.

For example, say if an audio file was 500 MB. DeBlytes partially downloads parts of the audio files so you can save RAM and GPU. You can enable DeBlytes in Settings >> Applications >> DeBlytes.dylib >> Enable: On. 

⚠️ WARNING ⚠️
When you enable DeBlytes, you cannot use the playback slider until it is fully downloaded. DeBlytes only downloads 10 MB of the audio per second. You can configure it in Settings >> Applications >> DeBlytes.dylib >> Slider to control how much to download per second. 1-50 MBs.

FocusOnMe:
FocusOnMe is a Dylib that prevents you from Backgrounding the Audio. This is configurable in Settings >> Applications >> FocusOnMe.dylib >> Enable: [ON/OFF]

This might require an app restart.

Developer’s Note: you shouldn’t enable this unless you are strict about RAM and Power usage.

Suitcase:
Suitcase is an audio unzipper. (Unzips .zip files and gets only the audio files.)

When enabling this, you will see an icon with a zip icon, click it and click your zip files. It will unzip all your audio files, including sub-folders.

However, it will require VirtualList, which is an Application we will get into later on.


VirtualList:
VirtualList is a Dylib that is very important to have. Let me explain.

VirtualList can add access to separate Playlists, up to 100,000+ playlists. Also, sub-playlists are available.

Here is an example of using VirtualList:

// this is just a gimmick of the code I want.

import playlist from virtuallist;

virtuallist.create(playlist);
virtuallist.create(playlist/playlist_2);
virtuallist.display();

VirtualList helps you organize playlists and sub-playlists so you won’t have to keep mixing songs every time.

There is buttons in the Library with <= and playlist number and =>.

Each playlist represents its own layer.

To enable VirtualList, Settings >> Applications >> VirtualList.dylib >> Enable: On.

BetterMusic:
BetterMusic is an entire music studio that:

Speed/Pitch
Reverb/Volume
Bass Booster
MP3/WAV Converters
Trim
Remove Vocals
Exports the BetterMusic Song into all the edits you put on it.

If you want to save this as a preset, it will export the song and the preset file [NAME].bettermusic.

You can choose to upload the .bettermusic file back in anytime!

You can find this App on the MP3 Player of the MusicPlayer, it’s a button on the top-right, it looks like a Radio. Click on it and it can edit your current song.

VolumeWarning:
VolumeWarning is a Dylib that allows you to set songs that have loud soundwaves.

You can also manually set songs as loud with the ! Button in the MP3 Player. It will expose your current playlist to set Boolean “VolumeWarning” to Yes.

However, it will automatically skip over the song, you can configure that in Settings >> Applications >> VolumeWarning.dylib >> “Automatically skip over loud songs”, but, when turned off, it will confirm if you want to play this song, even if you play the song, it will automatically turn your volume down to 25%, no matter what.

VolumeWarning can automatically set songs as loud whenever it passes 20 db or more.

Configurable in Settings >> Applications >> VolumeWarning.dylib >> “turn on AutoWarn” >> “slider that slides to 10-200 Db”.
