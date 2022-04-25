; function.s - handler for changing the state of the tracker
; predominantly originating through keystrokes, but also mouse actions
; and perhaps other inputs in the future


.scope Function

OP_UNDO = 1
OP_REDO = 2
OP_BACKSPACE = 3
OP_INSERT = 4
OP_COPY = 5

note_entry_dispatch_value: .byte $ff
op_dispatch_flag: .byte $00

tmp1: .res 1
tmp2: .res 1
tmp3: .res 1

copy:
    lda xf_state
    cmp #XF_STATE_PATTERN_EDITOR
    bne :+
        jmp Clipboard::copy_grid_cells
    :

    rts


decrement_grid_cursor:
    ldx Grid::cursor_position
    dex
    cpx #2
    bne :+
        dex
        dex
    :
    cpx #9
    bcc @end
    jsr decrement_grid_x
    ldx #8
@end:
    stx Grid::cursor_position
    inc redraw
    rts

decrement_grid_octave:
    ldy Grid::octave
    bne :+
        bra @exit
    :
    dec Grid::octave
@exit:
    inc redraw
    rts

decrement_grid_step:
    ldy Grid::step
    bne :+
        bra @exit
    :
    dec Grid::step
@exit:
    inc redraw
    rts


decrement_grid_x:
    jsr grid_selection_start
decrement_grid_x_without_starting_selection:
    ldy Grid::x_position
    bne :+
        ldy #(Grid::NUM_CHANNELS - 1)
        sty Grid::x_position
        bra @exit
    :
    dec Grid::x_position
@exit:
    jsr grid_selection_continue
    inc redraw
    rts


decrement_grid_y:
    jsr grid_selection_start
    ldy Grid::y_position
    bne :+
        ldy Grid::global_pattern_length
        dey
        sty Grid::y_position
        jsr decrement_sequencer_y
        bra @exit
    :
    dec Grid::y_position
@exit:
    jsr grid_selection_continue
    inc redraw
    rts

decrement_grid_y_page:
    jsr grid_selection_start
    lda Grid::y_position
    sec
    sbc #16
    bcs :+
        lda #0
    :
    sta Grid::y_position
    jsr grid_selection_continue
    inc redraw
    rts

decrement_grid_y_steps:
    ldy Grid::step
    bne @advance_step
    iny
@advance_step:
    phy
    jsr decrement_grid_y
    ply
    dey
    bne @advance_step
@end:
    rts


decrement_sequencer_y:
    ldy Sequencer::y_position
    bne :+
        ldy Sequencer::max_frame
        sty Sequencer::y_position
        bra @exit
    :
    dec Sequencer::y_position
@exit:
    inc redraw
    rts


decrement_sequencer_y_page:
    lda Sequencer::y_position
    sec
    sbc #4
    bcs :+
        lda #0
    :
    sta Sequencer::y_position
    inc redraw
    rts


delete_cell_above:
    ; if we're at the top of the grid, we do nothing
    ldy Grid::y_position
    beq @end
    dey
    sty tmp1

    ; we need to shift everything up in this column from cursor position down
    ; to the end of the pattern
@loop:
    ldy tmp1
    ldx Grid::x_position
    jsr Grid::set_lookup_addr

    iny
    cpy Grid::global_pattern_length
    dey
    bcs @empty_cell
@copy_cell:
    lda x16::Reg::RAMBank
    pha
    jsr Undo::store_pattern_cell
    pla
    sta x16::Reg::RAMBank

    ldy #0
    :
        phy

        tya
        clc
        adc #(8*Grid::NUM_CHANNELS)
        tay
        lda (Grid::lookup_addr),y
        ply
        sta (Grid::lookup_addr),y

        iny
        cpy #8
        bcc :-

    inc tmp1
    bra @loop

@empty_cell:
    lda x16::Reg::RAMBank
    pha

    jsr Undo::store_pattern_cell
    jsr Undo::mark_checkpoint

    pla
    sta x16::Reg::RAMBank


    lda #0
    ldy #0
    :
        sta (Grid::lookup_addr),y
        iny
        cpy #8
        bcc :-
@finalize:
    jsr decrement_grid_y
@end:
    rts


delete_selection:
    ; tmp1 = x, tmp2 = y
    lda Grid::selection_active
    beq @end

    ldx Grid::selection_left_x
    stx tmp1
    ldy Grid::selection_top_y
    sty tmp2
@loop:
    ldx tmp1
    ldy tmp2
    jsr Undo::store_pattern_cell
    ldx tmp1
    ldy tmp2
    jsr Grid::set_lookup_addr
    lda #0
    ldy #0
    :
        sta (Grid::lookup_addr),y
        iny
        cpy #8
        bcc :-
    ; advance x
    inc tmp1
    lda tmp1
    cmp Grid::selection_right_x
    beq @loop
    bcc @loop

    ; reset x and advance y
    lda Grid::selection_left_x
    sta tmp1

    inc tmp2
    lda tmp2
    cmp Grid::selection_bottom_y
    beq @loop
    bcc @loop

    jsr Undo::mark_checkpoint
    inc redraw
@end:
    rts


dispatch_backspace:
    lda #OP_BACKSPACE
    sta op_dispatch_flag
    rts

dispatch_copy:
    lda #OP_COPY
    sta op_dispatch_flag
    rts

dispatch_insert:
    lda #OP_INSERT
    sta op_dispatch_flag
    rts


dispatch_note_entry: ; make note entry happen outside of IRQ
    ; .A = notecode, we need convert to note value (MIDI number)
    cmp #$ff ; note delete
    beq @note_delete
    cmp #$fe ; note cut
    beq @note_cut
    cmp #$fd ; note release
    beq @note_release

    dec
    sta note_entry_dispatch_value
    ; note stored is 0 for C0, we need to add the octave+1 so that 12 is C0
    clc
    lda #0
    ldy Grid::octave
    iny
@octave_loop:
    adc #12
    dey
    bne @octave_loop
    adc note_entry_dispatch_value
    bra @end
@note_delete:
    lda #0
    bra @end
@note_cut:
    lda #1
    bra @end
@note_release:
    lda #2
@end:
    cmp #$80 ; clamp to 0-127 here, cancel entry if >= 128
    bcc :+
        lda #$ff
    :
    sta note_entry_dispatch_value
    rts

dispatch_redo:
    lda #OP_REDO
    sta op_dispatch_flag
    rts

dispatch_undo:
    lda #OP_UNDO
    sta op_dispatch_flag
    rts




grid_select_all:
    lda #2
    sta Grid::selection_active
    lda Grid::global_pattern_length
    dec
    sta Grid::selection_bottom_y
    lda #(Grid::NUM_CHANNELS-1)
    sta Grid::selection_right_x
    stz Grid::selection_left_x
    stz Grid::selection_top_y
    inc redraw
    rts

grid_select_none:
    stz Grid::selection_active
    inc redraw
    rts

grid_selection_start:
    lda GKeyboard::modkeys
    and #(GKeyboard::MOD_LSHIFT|GKeyboard::MOD_RSHIFT)
    beq @end

    lda Grid::selection_active
    bne :+
        lda Grid::x_position
        sta Grid::selection_left_x
        sta Grid::selection_right_x
        lda Grid::y_position
        sta Grid::selection_top_y
        sta Grid::selection_bottom_y
        lda #1
        sta Grid::selection_active
        bra @end
    :
    and #3
    cmp #2
    bne :+
        stz Grid::selection_active
        jmp grid_selection_start ; starting a new selection
    :
@end:
    rts




grid_selection_continue:
    lda GKeyboard::modkeys
    and #(GKeyboard::MOD_LSHIFT|GKeyboard::MOD_RSHIFT)
    bne :+
        jmp @noshift
    :
    ; bail out if we aren't continuing a selection
    lda Grid::selection_active
    and #1
    bne :+
        jmp @noshift
    :

@check_y_extended:
    lda Grid::selection_bottom_y
    cmp Grid::selection_top_y
    bne @y_extended
    ; y is not extended yet
    cmp Grid::y_position
    beq @check_x_extended ; y is unextended, but we're not extendeding it

    ; now we're going to determine our y extend direction here because
    ; y is about to be extended this frame
    bcc @extend_down ; selection top (and bottom) is less than new y pos,
                     ; so we extend down.
                     ; y increasing means selection is extending downward
@extend_up:
    smb2 Grid::selection_active
    bra @y_extended
@extend_down:
    rmb2 Grid::selection_active
@y_extended:
    bbr2 Grid::selection_active,@new_bottom
@new_top:
    lda Grid::y_position
    sta Grid::selection_top_y
    bra @check_x_extended
@new_bottom:
    lda Grid::y_position
    sta Grid::selection_bottom_y

@check_x_extended:
    lda Grid::selection_right_x
    cmp Grid::selection_left_x
    bne @x_extended
    ; x is not extended yet
    cmp Grid::x_position
    beq @check_y_inverted ; x is unextended, but we're not extendeding it

    ; now we're going to determine our x extend direction here because
    ; x is about to be extended this frame
    bcc @extend_right ; selection left (and right) is less than new x pos,
                     ; so we extend right.
                     ; x increasing means selection is extending rightward

@extend_left:
    smb3 Grid::selection_active
    bra @x_extended
@extend_right:
    rmb3 Grid::selection_active
@x_extended:
    bbr3 Grid::selection_active,@new_right
@new_left:
    lda Grid::x_position
    sta Grid::selection_left_x
    bra @check_y_inverted
@new_right:
    lda Grid::x_position
    sta Grid::selection_right_x

@check_y_inverted:
    lda Grid::selection_bottom_y
    cmp Grid::selection_top_y
    bcs @y_not_inverted
    ; y top and bottom switched places here
    pha
    lda Grid::selection_top_y
    sta Grid::selection_bottom_y
    pla
    sta Grid::selection_top_y
    lda Grid::selection_active
    eor #%00000100 ; flip the y estend direction bit
    sta Grid::selection_active
@y_not_inverted:

@check_x_inverted:
    lda Grid::selection_right_x
    cmp Grid::selection_left_x
    bcs @x_not_inverted
    ; x left and right switched places here
    pha
    lda Grid::selection_left_x
    sta Grid::selection_right_x
    pla
    sta Grid::selection_left_x
    lda Grid::selection_active
    eor #%00001000 ; flip the x estend direction bit
    sta Grid::selection_active
@x_not_inverted:

    bra @end
@noshift:
    lda Grid::selection_active
    and #3
    cmp #1
    bne @end
    lda #2
    sta Grid::selection_active
@end:
    rts



increment_grid_cursor:
    ldx Grid::cursor_position
    inx
    cpx #1
    bne :+
        inx
        inx
    :
    cpx #9
    bcc :+
        jsr increment_grid_x
        ldx #0
    :
    stx Grid::cursor_position
    inc redraw
    rts

increment_grid_x:
    jsr grid_selection_start
    ldy Grid::x_position
    cpy #(Grid::NUM_CHANNELS - 1)
    bcc :+
        stz Grid::x_position
        bra @exit
    :
    inc Grid::x_position
@exit:
    jsr grid_selection_continue
    inc redraw
    rts

increment_grid_octave:
    ldy Grid::octave
    cpy #Grid::MAX_OCTAVE
    bcc :+
        bra @exit
    :
    inc Grid::octave
@exit:
    inc redraw
    rts

increment_grid_step:
    ldy Grid::step
    cpy #Grid::MAX_STEP
    bcc :+
        bra @exit
    :
    inc Grid::step
@exit:
    inc redraw
    rts



increment_grid_y:
    jsr grid_selection_start
    inc Grid::y_position
    ldy Grid::y_position
    cpy Grid::global_pattern_length
    bcc :+
        stz Grid::y_position
        jsr increment_sequencer_y
        bra @exit
    :
@exit:
    jsr grid_selection_continue
    inc redraw
    rts

increment_grid_y_page:
    jsr grid_selection_start
    lda Grid::y_position
    clc
    adc #16
    bcs @clamp

    cmp Grid::global_pattern_length
    bcc @end

@clamp:
    lda Grid::global_pattern_length
    dec
@end:
    sta Grid::y_position
    jsr grid_selection_continue
    inc redraw
    rts


increment_grid_y_steps:
    ldy Grid::step
    bne @advance_step
    iny
@advance_step:
    phy
    jsr increment_grid_y
    ply
    dey
    bne @advance_step
@end:
    rts

increment_sequencer_y:
    ldy Sequencer::y_position
    cpy Sequencer::max_frame
    bcc :+
        stz Sequencer::y_position
        bra @exit
    :
    inc Sequencer::y_position
@exit:
    inc redraw
    rts

increment_sequencer_y_page:
    lda Sequencer::y_position
    clc
    adc #4
    bcs @clamp

    cmp Sequencer::max_frame
    bcc @end

@clamp:
    lda Sequencer::max_frame
@end:
    sta Sequencer::y_position
    inc redraw
    rts


insert_cell:

    ldy Grid::global_pattern_length
    dey
    dey
    sty tmp1
    ; to get us back to the row where we did the insert, we have to
    ; store an undo event here first
    ldy Grid::y_position
    ldx Grid::x_position
    jsr Undo::store_pattern_cell

    ; we need to shift everything down in this column starting from the end
    ; of the pattern and going toward the current position
@copy_cell:
    ldx Grid::x_position
    ldy tmp1
    iny
    jsr Undo::store_pattern_cell

    ldx Grid::x_position
    ldy tmp1
    jsr Grid::set_lookup_addr


    ldy #0
    :
        phy
        lda (Grid::lookup_addr),y
        pha

        tya
        clc
        adc #(8*Grid::NUM_CHANNELS)
        tay

        pla
        sta (Grid::lookup_addr),y

        ply
        iny
        cpy #8
        bcc :-

    ldy tmp1
    cpy Grid::y_position
    beq @empty_cell

    dec tmp1
    bra @copy_cell

@empty_cell:
    lda x16::Reg::RAMBank
    pha

    jsr Undo::store_pattern_cell
    jsr Undo::mark_checkpoint

    pla
    sta x16::Reg::RAMBank


    lda #0
    ldy #0
    :
        sta (Grid::lookup_addr),y
        iny
        cpy #8
        bcc :-

@finalize:
    inc redraw
@end:
    rts



note_entry:
    ; first put the old value on the undo stack
    ldx Grid::x_position
    ldy Grid::y_position
    jsr Undo::store_pattern_cell
    jsr Undo::mark_checkpoint

    ; now actually apply the note
    ldx Grid::x_position
    ldy Grid::y_position

    jsr Grid::set_lookup_addr ; set the grid lookup_addr value to the beginning
                              ; of the note data for the current row/column
                              ; this affects RAM bank as well
    lda note_entry_dispatch_value
    sta (Grid::lookup_addr) ; zero offset, this is the note column
    pha

    ldy #1
    lda Instruments::y_position ; currently selected instrument
    sta (Grid::lookup_addr),y ; #1 offset, this is the instrument number
    tay
    lda #$ff
    sta note_entry_dispatch_value

    pla
    ldx Grid::x_position
    jsr play_note ; .A = note, .X = column, .Y = instrument

    inc redraw

    ldy Grid::step
    beq @end
@advance_step:
    phy
    jsr increment_grid_y
    ply
    dey
    bne @advance_step
@end:
    rts


play_note: ;.A = note, .X = column, .Y = instrument
    rts




set_grid_y:
    pha
    jsr grid_selection_start
    pla
    sta Grid::y_position
    jsr grid_selection_continue
    inc redraw
    rts

set_sequencer_y:
    sta Sequencer::y_position
    inc redraw
    rts



.endscope
