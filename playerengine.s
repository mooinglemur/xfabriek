.scope PlayerEngine


tmp8b: .res 8
tmp1: .res 1
tmp2: .res 1



.include "playerengine/ym_wait.s"
.include "playerengine/panic.s"
.include "playerengine/release_voices.s"
.include "playerengine/assign_voice_psg.s"
.include "playerengine/assign_voice_ym.s"
.include "playerengine/assign_voices.s"
.include "playerengine/load_row.s"
.include "playerengine/tick.s"



.endscope
