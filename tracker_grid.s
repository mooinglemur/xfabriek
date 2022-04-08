.scope Grid

x_position: .res 1 ; which tracker column (channel) are we in
y_position: .res 1 ; which tracker row are we in
cursor_position: .res 1 ; within the column (channel) where is the cursor?
global_frame_length: .res 1 ; set on file create/file load
base_bank: .res 1 ; where does tracker data start

NUM_CHANNELS = 8

draw: ; affects A,X,Y,xf_tmp1,xf_tmp2,xf_tmp3

    ; Top of grid
    VERA_SET_ADDR ($0206+$1B000),2

    ;lda #$A3
    ;sta VERA_data0

    ldx #NUM_CHANNELS
    :
        lda #$A1
        sta Vera::Reg::Data0
        lda #$A0
        sta Vera::Reg::Data0
        sta Vera::Reg::Data0
        sta Vera::Reg::Data0
        sta Vera::Reg::Data0
        sta Vera::Reg::Data0
        sta Vera::Reg::Data0
        sta Vera::Reg::Data0
        dex
        bne :-
    lda #$A2
    sta Vera::Reg::Data0


    ; cycle through 40 rows
    ; start on row 3
    lda #3
    sta xf_tmp1
    lda y_position
    sec
    sbc #20
    sta xf_tmp2
    stz xf_tmp3

@rowstart:
    lda #(1 | $10) ; high bank, stride = 1
    sta $9F22

    lda xf_tmp1 ; row number
  clc
  adc #$b0
    sta $9F21

    lda #2 ; one character over
    sta $9F20

    lda xf_tmp3
    beq :+
        jmp @blankrow
    :

    lda xf_tmp2
    ldy xf_tmp1
    cpy #23
    bcs :++
        cmp y_position
        bcc :+
            jmp @blankrow
        :
        bra @filledrow
    :

    ldy xf_tmp2
    cpy global_frame_length
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

    ; color current row
    lda xf_tmp2
    cmp y_position
    bne :+
        ldy #(XF_AUDITION_BG_COLOR | XF_BASE_FG_COLOR)
        bra @got_color
    :
    ; color every 16 rows
    lda xf_tmp2
    and #%11110000
    cmp xf_tmp2
    bne :+
        ldy #(XF_HILIGHT_BG_COLOR_2 | XF_BASE_FG_COLOR)
        bra @got_color
    :
    ; color every 4 rows
    lda xf_tmp2
    and #%11111100
    cmp xf_tmp2
    bne :+
        ldy #(XF_HILIGHT_BG_COLOR_1 | XF_BASE_FG_COLOR)
        bra @got_color
    :


@got_color:
    ldx #NUM_CHANNELS
    :
        lda #$A4
        sta Vera::Reg::Data0
        sty Vera::Reg::Data0
        lda #'.'
        sta Vera::Reg::Data0
        sty Vera::Reg::Data0
        sta Vera::Reg::Data0
        sty Vera::Reg::Data0
        sta Vera::Reg::Data0
        sty Vera::Reg::Data0
        sta Vera::Reg::Data0
        sty Vera::Reg::Data0
        sta Vera::Reg::Data0
        sty Vera::Reg::Data0
        sta Vera::Reg::Data0
        sty Vera::Reg::Data0
        sta Vera::Reg::Data0
        sty Vera::Reg::Data0
        dex
        bne :-
    lda #$A3
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
    :
        lda #$A3
        sta Vera::Reg::Data0
        sty Vera::Reg::Data0
        lda #' '
        sta Vera::Reg::Data0
        sty Vera::Reg::Data0
        sta Vera::Reg::Data0
        sty Vera::Reg::Data0
        sta Vera::Reg::Data0
        sty Vera::Reg::Data0
        sta Vera::Reg::Data0
        sty Vera::Reg::Data0
        sta Vera::Reg::Data0
        sty Vera::Reg::Data0
        sta Vera::Reg::Data0
        sty Vera::Reg::Data0
        sta Vera::Reg::Data0
        sty Vera::Reg::Data0
        dex
        bne :-
    lda #$A3
    sta Vera::Reg::Data0
    ldy #(XF_BASE_BG_COLOR|XF_BASE_FG_COLOR)
    sty Vera::Reg::Data0

@endofrow:
    lda xf_tmp3
    bne :+
        inc xf_tmp2


    :
    inc xf_tmp1
    lda xf_tmp1
    cmp #43
    bcs :+
        jmp @rowstart
    :

; now put the cursor where it belongs
    lda #(1 | $20) ; high page, stride = 2
    sta $9F22

    lda #23 ; row number
    clc
    adc #$b0
    sta $9F21

    lda x_position
    asl
    asl
    asl

    clc
    adc cursor_position
    adc #3
    asl
    ina

    sta $9F20

    lda #(XF_CURSOR_BG_COLOR | XF_BASE_FG_COLOR)
    sta Vera::Reg::Data0

    ldy cursor_position
    bne :+
        sta Vera::Reg::Data0
    :



;    lda #$81
;    sta VERA_data0
;    lda #$91
;    sta VERA_data0



;@colorcursorline:
;    lda #(0 | $20) ; low page, stride = 2
;    sta $9F22
;
;    lda #23; row number
;    sta $9F21
;
;    lda #7 ; address color memory inside grid
;    sta $9F20
;
;    ldx #70
;    lda #%00100001
;    :
;        sta VERA_data0
;        dex
;        bne :-
;
    rts
.endscope
