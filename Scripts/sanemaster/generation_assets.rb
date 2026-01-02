# frozen_string_literal: true

module SaneMasterModules
  # Test asset generation using FFmpeg
  module GenerationAssets
    include Base

    def generate_test_assets
      puts '🎬 --- [ SANEMASTER TEST ASSETS ] ---'
      puts 'Generating lightweight test media...'

      assets_dir = 'Tests/Assets'
      FileUtils.mkdir_p(assets_dir)

      unless system('which ffmpeg > /dev/null 2>&1')
        puts '❌ ffmpeg not found. Install: brew install ffmpeg'
        return
      end

      generate_test_video(assets_dir)
      generate_silence_audio(assets_dir)
      puts "\n✅ Test assets ready."
    end

    private

    def generate_test_video(assets_dir)
      video_path = "#{assets_dir}/test_video.mp4"
      if File.exist?(video_path)
        puts '  ⚠️  test_video.mp4 already exists, skipping'
        return
      end

      print '  Generating test_video.mp4 (5s, 640x480)... '
      cmd = "ffmpeg -f lavfi -i testsrc=duration=5:size=640x480:rate=30 -c:v libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p -y #{video_path} 2>/dev/null"
      puts system(cmd) ? '✅' : '❌ Failed'
    end

    def generate_silence_audio(assets_dir)
      silence_path = "#{assets_dir}/test_silence.mp4"
      if File.exist?(silence_path)
        puts '  ⚠️  test_silence.mp4 already exists, skipping'
        return
      end

      print '  Generating test_silence.mp4 (5s silence)... '
      cmd = "ffmpeg -f lavfi -i anullsrc=r=44100:cl=stereo -t 5 -c:a aac -y #{silence_path} 2>/dev/null"
      puts system(cmd) ? '✅' : '❌ Failed'
    end
  end
end
