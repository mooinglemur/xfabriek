.proc entry_callback
    bcs end ; carry indicates abort
    ldx GridState::x_position
    ldy SeqState::y_position
    jsr Undo::store_sequencer_row

    ldy SeqState::y_position
    jsr SeqState::set_lookup_addr

    jsr TextField::get_byte_from_hex
    cmp SeqState::max_pattern
    beq :+
        bcc :+
        lda SeqState::max_pattern
    :
    ldy GridState::x_position
    sta (SeqState::lookup_addr),y

    jsr Undo::mark_checkpoint
    inc GridState::x_position
    lda GridState::x_position
    cmp #GridState::NUM_CHANNELS
    bcc end
    stz GridState::x_position
end:
    lda #XF_STATE_SEQUENCER
    sta xf_state
    inc redraw
    rts
.endproc
