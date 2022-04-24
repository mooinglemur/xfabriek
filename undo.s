.scope Undo

base_bank: .res 1
; undo/redo stack sizes, this can be > 8 bits if we end up being super generous
undo_size: .res 2
redo_size: .res 2

; see below for "undo group" markers
checkpoint: .byte $01

; temp space
tmp_undo_buffer: .res 16
.pushseg
.segment "ZEROPAGE"
lookup_addr: .res 2
.popseg

store_pattern_cell: ; takes in .X = channel column, .Y = row, affects all registers
    lda #1
    sta tmp_undo_buffer
    lda checkpoint
    lda #2
    sta checkpoint
    sta tmp_undo_buffer+1
    stx tmp_undo_buffer+3
    sty tmp_undo_buffer+4

    jsr Grid::set_lookup_addr ; set lookup while x/y are still untouched
    ; determine the actual pattern by looking up the index in the currently displayed patterns
    lda Grid::channel_to_pattern,x
    sta tmp_undo_buffer+2
    lda Sequencer::mix
    sta tmp_undo_buffer+5
    lda Sequencer::y_position
    sta tmp_undo_buffer+6
    stz tmp_undo_buffer+7
    ldy #0
    :
        lda (Grid::lookup_addr),y
        sta tmp_undo_buffer+8,y
        iny
        cpy #8
        bcc :-

    lda base_bank
    sta x16::Reg::RAMBank

; we need to invalidate the entire redo stack upon storing a new undo event
; let's do that first
    jsr invalidate_redo_stack
; advance the pointer to store our new event
    jsr advance_undo_pointer

; transfer the tmp_undo_buffer
    ldy #0
    :
        lda tmp_undo_buffer,y
        sta (lookup_addr),y

        iny
        cpy #16
        bcc :-

; make sure a redo for this event doesn't go past here until there are more events
    jsr mark_redo_stop


    rts

invalidate_redo_stack:
    lda lookup_addr
    pha
    lda lookup_addr+1
    pha

@loop:
    ;return if zero
    lda redo_size
    bne @continue_loop
    lda redo_size+1
    bne @continue_loop
    bra @end
@continue_loop:
    jsr advance_undo_pointer
    ldy #1
    lda (lookup_addr),y
    cmp #1
    beq @continue_loop
    lda #0
    sta (lookup_addr),y

    lda redo_size
    sec
    sbc #1
    sta redo_size
    lda redo_size+1
    sbc #0
    sta redo_size+1
    bra @loop
@end:
    pla
    sta lookup_addr+1
    pla
    sta lookup_addr
    rts


mark_checkpoint: ; no inputs, we call this to mark the last undo event as
                 ; the final event in a series that will get undone as a group
                 ; if the undo is called
    lda #1
    sta checkpoint
    clc
    adc undo_size
    sta undo_size
    lda undo_size+1
    adc #0
    sta undo_size+1

    rts


mark_redo_stop: ; affects .A, .Y
    ; this does nothing but ensure the next event slot is marked as a stop point
    ; so that redo stops at the right point

    ; store current lookup addr on stack
    lda lookup_addr
    pha
    lda lookup_addr+1
    pha

    ; temporarily advance the pointer
    jsr advance_undo_pointer
    ; if we're clobbering a start point, we need to decrement our undo stack
    ldy #1
    lda (lookup_addr),y
    cmp #2
    bne :+
    ;; actually, if undo_size does dip below zero, it means we've wrapped around
    ;; and stored more data in one group than can fit in the entire buffer
    ;; so I think we actually want to allow it to drop below zero

        lda undo_size
        sec
        sbc #1
        sta undo_size
        lda undo_size+1
        sbc #0
        sta undo_size+1
    :

    ; mark the stop point

    lda #0
    sta (lookup_addr),y

    ; restore the old pointer
    pla
    sta lookup_addr+1
    pla
    sta lookup_addr

    rts


advance_undo_pointer: ; affects .A
    ; check to see if the next event is going to wrap around the buffer
    lda lookup_addr
    cmp #$F0
    bne @no_wrap
    lda lookup_addr+1
    cmp #$BF
    bne @no_wrap
    ; we are going to wrap
    stz lookup_addr
    lda #$A0
    sta lookup_addr+1
    bra @ptr_advanced
@no_wrap:
    lda lookup_addr
    clc
    adc #16
    sta lookup_addr
    lda lookup_addr+1
    adc #0
    sta lookup_addr+1
@ptr_advanced:
    rts

reverse_undo_pointer: ; affects .A, we run this after applying an undo event
    ; check to see if the next event is going to wrap around the buffer
    lda lookup_addr
    bne @no_wrap
    lda lookup_addr+1
    cmp #$A0
    bne @no_wrap
    ; we are going to wrap
    lda #$F0
    sta lookup_addr
    lda #$BF
    sta lookup_addr+1
    bra @ptr_advanced
@no_wrap:
    lda lookup_addr
    sec
    sbc #16
    sta lookup_addr
    lda lookup_addr+1
    sbc #0
    sta lookup_addr+1
@ptr_advanced:
    rts


handle_undo_redo_pattern_cell:
    ; the operation here is the same whether we're undoing or redoing
    ; we swap the data in the undo buffer with that in grid memory

    lda base_bank
    sta x16::Reg::RAMBank

    ; first, copy the undo event into temp
    ldy #0
    :
        lda (lookup_addr),y
        sta tmp_undo_buffer,y
        iny
        cpy #16
        bcc :-

    ; first set the state of the sequencer table to that of the event
    lda tmp_undo_buffer+5 ; set the mix number
    sta Sequencer::mix
    lda tmp_undo_buffer+6 ; set row number
    sta Sequencer::y_position
    ; we need to trigger the sequencer redraw to populate Grid state
    jsr Sequencer::draw
    ; now position the Grid memory pointer (changes bank too)
    ldx tmp_undo_buffer+3
    stx Grid::x_position
    ldy tmp_undo_buffer+4
    sty Grid::y_position
    jsr Grid::set_lookup_addr
    ; now swap the contents
    ldy #0
    :
        lda (Grid::lookup_addr),y
        pha
        lda tmp_undo_buffer+8,y
        sta (Grid::lookup_addr),y
        pla
        sta tmp_undo_buffer+8,y

        iny
        cpy #8
        bcc :-

    ; reset the bank to the undo bank
    lda base_bank
    sta x16::Reg::RAMBank

    ; now copy the event back into the undo space
    ldy #0
    :
        lda tmp_undo_buffer,y
        sta (lookup_addr),y
        iny
        cpy #16
        bcc :-

    ; we're done
    rts

undo:
    ; apply one undo group
    lda undo_size
    bne @can_undo
    lda undo_size+1
    bne @can_undo
    rts ; immediately return if we can't undo
@can_undo:
    ; pointer should be at the most recent undo event
    ; reset the bank to the undo bank
    lda base_bank
    sta x16::Reg::RAMBank

    ldy #0
    lda (lookup_addr),y
    cmp #$01 ; pattern cell
    beq @undo_pattern_cell
    cmp #$02 ; sequencer cell
    beq @undo_sequencer_cell
    bra @check_end_of_undo_group
@undo_pattern_cell:
    jsr handle_undo_redo_pattern_cell
    bra @check_end_of_undo_group
@undo_sequencer_cell:
    bra @check_end_of_undo_group
@check_end_of_undo_group:
    ldy #1
    lda (lookup_addr),y
    cmp #2
    bne @continue
    ; we just finished an undo group, back it up once more and stop
    jsr reverse_undo_pointer

    ; now decrement undo_size and increment redo_size
    lda undo_size
    sec
    sbc #1
    sta undo_size
    lda undo_size+1
    sbc #0
    sta undo_size+1

    lda redo_size
    clc
    adc #1
    sta redo_size
    lda redo_size+1
    adc #0
    sta redo_size+1

    lda #1
    sta checkpoint
    bra @end
@continue:
    jsr reverse_undo_pointer
    bra @can_undo
@end:
    inc redraw
    rts


redo:
    ; apply one redo group
    lda redo_size
    bne @can_redo
    lda redo_size+1
    bne @can_redo
    rts ; immediately return if we can't redo
@can_redo:
    ; pointer should be behind the first redoable event
    ; reset the bank to the undo bank, and advance
    lda base_bank
    sta x16::Reg::RAMBank
    jsr advance_undo_pointer

    ldy #0
    lda (lookup_addr),y
    cmp #$01 ; pattern cell
    beq @redo_pattern_cell
    cmp #$02 ; sequencer cell
    beq @redo_sequencer_cell
    bra @check_end_of_redo_group
@redo_pattern_cell:
    jsr handle_undo_redo_pattern_cell
    bra @check_end_of_redo_group
@redo_sequencer_cell:
    bra @check_end_of_redo_group
@check_end_of_redo_group:
    jsr advance_undo_pointer
    ldy #1
    lda (lookup_addr),y
    cmp #1
    beq @continue
    ; we just finished a redo group, back it up once more and stop
    jsr reverse_undo_pointer

    ; now decrement redo_size and increment undo_size
    lda redo_size
    sec
    sbc #1
    sta redo_size
    lda redo_size+1
    sbc #0
    sta redo_size+1

    lda undo_size
    clc
    adc #1
    sta undo_size

    lda #1
    sta checkpoint
    bra @end
@continue:
    bra @can_redo
@end:
    inc redraw
    rts



; undo data format
; 16 bytes per event

;00 - format
;       01 - pattern cell
;       02 - sequencer cell
;01 - undo group
;       00 - stop point, or uninitialized
;       01 - start point, first event in a group
;       02 - continuation, subsequent events in a group


; for format 01 (tracker grid cell)
;02 - pattern number <-- code doesn't use this directly at least for now
;03 - channel number (x column)
;04 - row number (y column)
;05 - mix number  <-- for restoring the UI
;06 - sequencer row <-- for restoring the UI
;07 - for possible future use
;08-0F - cell data state

; for format 02 (sequencer cell)
;02 - mix number
;03 - column
;04 - row
;05-07 - for possible future use
;08 - value
;09-0F - for possible future use


.endscope