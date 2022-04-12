.scope Sequencer

x_position: .res 1 ; which tracker column (channel) are we in
y_position: .res 1 ; which tracker row are we in
max_frame: .res 1 ; the last frame in the sequencer

NUM_CHANNELS = 8
SEQUENCER_LOCATION_X = 1
SEQUENCER_LOCATION_Y = 44
SEQUENCER_GRID_ROWS = 9


draw: ; affects A,X,Y,xf_tmp1,xf_tmp2,xf_tmp3

    ; Top of grid
    VERA_SET_ADDR ((SEQUENCER_LOCATION_Y * 256)+((SEQUENCER_LOCATION_X+2)*2)+Vera::VRAM_text),2

    ;lda #$A3
    ;sta VERA_data0

    lda #$70
    sta Vera::Reg::Data0
    ldx #(NUM_CHANNELS-1)
    :
        lda #$40
        sta Vera::Reg::Data0
        sta Vera::Reg::Data0
        lda #$72
        sta Vera::Reg::Data0
        dex
        bne :-
    lda #$40
    sta Vera::Reg::Data0
    sta Vera::Reg::Data0

    lda #$6E
    sta Vera::Reg::Data0


    ; cycle through 4 rows
    ; start on row SEQUENCER_LOCATION+1
    lda #SEQUENCER_LOCATION_Y+1
    sta xf_tmp1
    lda y_position
    sec
    sbc #4
    sta xf_tmp2
    stz xf_tmp3

@rowstart:
    lda #(1 | $10) ; high bank, stride = 1
    sta $9F22

    lda xf_tmp1 ; row number
    clc
    adc #$b0
    sta $9F21

    lda #(SEQUENCER_LOCATION_X*2) ; grid start
    sta $9F20

    lda xf_tmp3
    beq :+
        jmp @blankrow
    :

    lda xf_tmp2
    ldy xf_tmp1
    cpy #(SEQUENCER_LOCATION_Y+(SEQUENCER_GRID_ROWS/2)+1)
    bcs :++
        cmp y_position
        bcc :+
            jmp @blankrow
        :
        bra @filledrow
    :

    ldy xf_tmp2
    cpy max_frame
    bne :+
        inc xf_tmp3
    :
    cmp y_position
    bcs @filledrow

@filledrow:
    jsr xf_byte_to_hex
    ldy #(XF_BASE_BG_COLOR | XF_BASE_FG_COLOR)
    sta Vera::Reg::Data0
    sty Vera::Reg::Data0
    stx Vera::Reg::Data0
    sty Vera::Reg::Data0


@got_color:
    ldx #NUM_CHANNELS
    :
        lda #$5D
        sta Vera::Reg::Data0
        sty Vera::Reg::Data0
        lda #'.'
        sta Vera::Reg::Data0
        sty Vera::Reg::Data0
        sta Vera::Reg::Data0
        sty Vera::Reg::Data0
        dex
        bne :-
    lda #$5D
    sta Vera::Reg::Data0
    ldy #(XF_BASE_BG_COLOR|XF_BASE_FG_COLOR)
    sty Vera::Reg::Data0

    bra @endofrow
@blankrow:
    lda #$20
    ldy #%00000001 ; color value for blank row is 0 bg, 1 fg
    sta Vera::Reg::Data0
    sty Vera::Reg::Data0
    sta Vera::Reg::Data0
    sty Vera::Reg::Data0

    ldx #NUM_CHANNELS
    lda #$5D
    sta Vera::Reg::Data0
    sty Vera::Reg::Data0
    :
        lda #' '
        sta Vera::Reg::Data0
        sty Vera::Reg::Data0
        sta Vera::Reg::Data0
        sty Vera::Reg::Data0
        lda #$5D
        sta Vera::Reg::Data0
        sty Vera::Reg::Data0
        dex
        bne :-

@endofrow:
    lda xf_tmp3
    bne :+
        inc xf_tmp2


    :
    inc xf_tmp1
    lda xf_tmp1
    cmp #(SEQUENCER_LOCATION_Y+SEQUENCER_GRID_ROWS+1)
    bcs :+
        jmp @rowstart
    :

;   Bottom of grid
    VERA_SET_ADDR (((SEQUENCER_LOCATION_Y+SEQUENCER_GRID_ROWS+1) * 256)+((SEQUENCER_LOCATION_X+2)*2)+Vera::VRAM_text),2

    ;lda #$A3
    ;sta VERA_data0

    lda #$6D
    sta Vera::Reg::Data0
    ldx #(NUM_CHANNELS-1)
    :
        lda #$40
        sta Vera::Reg::Data0
        sta Vera::Reg::Data0
        lda #$71
        sta Vera::Reg::Data0
        dex
        bne :-
    lda #$40
    sta Vera::Reg::Data0
    sta Vera::Reg::Data0

    lda #$7D
    sta Vera::Reg::Data0




; now put the cursor where it belongs
    lda #(1 | $20) ; high page, stride = 2
    sta $9F22

    lda #(SEQUENCER_LOCATION_Y+SEQUENCER_GRID_ROWS/2+1)
    clc
    adc #$b0
    sta $9F21

    lda Grid::x_position
    asl
    clc
    adc Grid::x_position

    adc #4
    asl
    ina

    sta $9F20

    lda #(XF_CURSOR_BG_COLOR | XF_BASE_FG_COLOR)
    sta Vera::Reg::Data0
    sta Vera::Reg::Data0


    rts
.endscope