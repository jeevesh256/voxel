import 'radio_station.dart';

final List<RadioStation> popularStations = [
  RadioStation(
    id: 'bbc_radio_1',
    name: 'BBC Radio 1',
    genre: 'Pop',
    streamUrl: 'https://stream.live.vc.bbcmedia.co.uk/bbc_radio_one',
    artworkUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/4/4e/BBC_Radio_1_Logo_2021.svg/1200px-BBC_Radio_1_Logo_2021.svg.png',
    country: 'UK',
  ),
  RadioStation(
    id: 'bbc_radio_2',
    name: 'BBC Radio 2',
    genre: 'Adult Contemporary',
    streamUrl: 'https://stream.live.vc.bbcmedia.co.uk/bbc_radio_two',
    artworkUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/7/7a/BBC_Radio_2_Logo_2021.svg/1200px-BBC_Radio_2_Logo_2021.svg.png',
    country: 'UK',
  ),
  RadioStation(
    id: 'npr',
    name: 'NPR',
    genre: 'News',
    streamUrl: 'https://npr-ice.streamguys1.com/live.mp3',
    artworkUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/8/8b/NPR_News_logo.svg/1200px-NPR_News_logo.svg.png',
    country: 'USA',
  ),
  RadioStation(
    id: 'apple_music_hits',
    name: 'Apple Music Hits',
    genre: 'Hits',
    streamUrl: 'https://streaming.apple.com/hits',
    artworkUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Features115/v4/7a/7e/2e/7a7e2e7a-7e2e-7a7e-2e7a-7e2e7a7e2e7a/AppleMusicHits.png/1200x1200bb.jpg',
    country: 'USA',
  ),
  RadioStation(
    id: 'classic_fm',
    name: 'Classic FM',
    genre: 'Classical',
    streamUrl: 'https://media-ice.musicradio.com/ClassicFMMP3',
    artworkUrl: 'https://upload.wikimedia.org/wikipedia/en/2/2e/Classic_FM_logo.png',
    country: 'UK',
  ),
  RadioStation(
    id: 'jazz_fm',
    name: 'Jazz FM',
    genre: 'Jazz',
    streamUrl: 'https://media-ice.musicradio.com/JazzFMMP3',
    artworkUrl: 'https://upload.wikimedia.org/wikipedia/en/7/7e/Jazz_FM_logo.png',
    country: 'UK',
  ),
  // Add more stations as needed
];
