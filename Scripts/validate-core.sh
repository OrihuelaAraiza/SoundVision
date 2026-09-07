#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
validation_dir=$(mktemp -d /tmp/soundvision-validation.XXXXXX)
trap 'rm -rf "$validation_dir"' EXIT
xcrun swiftc \
  SoundVision/Models/SoundNode.swift \
  SoundVision/MusicLogic/SpatialParameterMapper.swift \
  SoundVision/MusicLogic/GraphSchedule.swift \
  SoundVision/MusicLogic/GraphTransport.swift \
  SoundVision/MusicLogic/Sequencer.swift \
  SoundVision/MusicLogic/CompositionState.swift \
  SoundVision/Persistence/CompositionStorage.swift \
  SoundVision/Audio/SpatialAudioSession.swift \
  SoundVision/Learning/MusicLesson.swift \
  SoundVision/Audio/VoiceSynthesis.swift \
  SoundVision/Audio/VoiceSchedule.swift \
  SoundVision/Audio/RealtimeVoice.swift \
  Scripts/Validation/main.swift -o "$validation_dir/validate"
"$validation_dir/validate"
