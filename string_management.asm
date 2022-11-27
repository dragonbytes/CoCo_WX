
; ------------------------------------------------
; search ascii string for first space, NULL, or CR 
; Entry: X = pointer to string to search 
; Exit: on success, carry clear, 
; 	 B = number of characters before terminator, X = pointing to terminating char 
; 	 on fail, carry set
; ------------------------------------------------
FIND_NEXT_SPACE_NULL_CR
	pshs 	A 

	clrb 
FIND_NEXT_SPACE_NULL_CR_NEXT
	lda 	,X+
	beq 	FIND_NEXT_SPACE_NULL_CR_END
	cmpa 	#$20
	beq 	FIND_NEXT_SPACE_NULL_CR_END
	cmpa 	#C$CR 
	beq 	FIND_NEXT_SPACE_NULL_CR_END
	incb 
	bne 	FIND_NEXT_SPACE_NULL_CR_NEXT
	orcc 	#1 	; set carry for overflow error
	puls 	A,PC 

FIND_NEXT_SPACE_NULL_CR_END
	leax 	-1,X 
	andcc 	#$FE 	; carry clear for success 
	puls 	A,PC 

; --------------------------------
; find next nonspace char/skip "white space" 
; Entry: X = pointer to string to search 
; 	  A = character it found. X = pointing to character it found
; 	carry set if overflow past 256 bytes or NULL is encoutered  
; --------------------------------
FIND_NEXT_NONSPACE_CHAR
	pshs 	B
	clrb 
FIND_NEXT_NONSPACE_CHAR_NEXT
	lda 	,X+
	beq 	FIND_NEXT_NONSPACE_CHAR_FAIL
	cmpa 	#$20
	bne 	FIND_NEXT_NONSPACE_CHAR_DONE
	decb 
	bne 	FIND_NEXT_NONSPACE_CHAR_NEXT
FIND_NEXT_NONSPACE_CHAR_FAIL
	leax 	-1,X 
	orcc 	#1
	puls 	B,PC 

FIND_NEXT_NONSPACE_CHAR_DONE
	leax 	-1,X 
	andcc 	#$FE
	puls 	B,PC 

; ----------------------------------------------------------------------------
; find next occurance of quote mark char
; Entry: X = ptr to string to search through
; Exit: success, X will be ptr to the char AFTER found quote mark. carry clear
;       fail, registers return to original value. carry set
; ----------------------------------------------------------------------------
FIND_NEXT_QUOTE_CHAR
	pshs  	X,D 

	clrb 
FIND_NEXT_QUOTE_CHAR_NEXT
	lda  	,X+
	cmpa 	#$22
	beq  	FIND_NEXT_QUOTE_CHAR_FOUND
	decb 
	bne  	FIND_NEXT_QUOTE_CHAR_NEXT
	; if here, overflow passed 256 bytes. report error
	orcc 	#1
	puls  	D,X,PC 

FIND_NEXT_QUOTE_CHAR_FOUND
	stx  	2,S  		; save return ptr to stack
	andcc 	#$FE 
	puls  	D,X,PC 


; ---------------------------------------------------------
; searches a string for a specific keyword, ignoring case, 
; one character at a time until it encounters end of buffer. 
; Entry: X = string to search, ignoring case.
; 	  Y = keyword to find (MUST BE IN CAPS)
;  	  searchEndPtr = set to where to stop looking for match
; Exit: success, X pointing to character after last matched char 
; ---------------------------------------------------------
STRING_SEARCH_BUFFER
	pshs 	Y,X,D 

STRING_SEARCH_BUFFER_NEXT_TRY
	ldy 	4,S 
STRING_SEARCH_BUFFER_NEXT_CHAR
	lda 	,Y 
	beq 	STRING_SEARCH_BUFFER_MATCHED
	lda 	,X+
	lbsr 	CONVERT_UPPERCASE
	cmpa 	,Y+
	beq 	STRING_SEARCH_BUFFER_NEXT_CHAR
	; if here, no match. advance origin point one char and start again 
	cmpx 	<searchEndPtr
	blo 	STRING_SEARCH_BUFFER_NEXT_TRY
STRING_SEARCH_BUFFER_FAIL
	orcc 	#1
	puls 	D,X,Y,PC 

STRING_SEARCH_BUFFER_MATCHED
	stx 	2,S 		; update X on the stack to reflect pointer to our successful match 
	andcc 	#$FE
	puls 	D,X,Y,PC 

; -----------------------------------------------------------------
; scan through weather code conditions table to find one
; that matches and then return correct index number for the
; graphical icons
; Entry: X = pointer to 3 character ascii weather code number to find
; Exit: A = index value to corresponding icon graphic
; -----------------------------------------------------------------
SEARCH_CONDITIONS_SYMBOL
	pshs 	Y,B 

	leay 	curCondCodeTableEnd,PCR 
	sty  	<tempPtr
	leay 	curCondCodeTable,PCR 
SEARCH_CONDITIONS_SYMBOL_CHECK_NEXT_SYMBOL
	ldd  	,X
	cmpd 	,Y 
	bne  	SEARCH_CONDITIONS_SYMBOL_NEXT_SYMBOL
	lda  	2,X 
	cmpa 	2,Y 
	bne  	SEARCH_CONDITIONS_SYMBOL_NEXT_SYMBOL
	; if here, we have a match. grab the index value for the corresponding icon graphic
	lda  	3,Y 
	andcc 	#$FE 
	puls  	B,Y,PC 

SEARCH_CONDITIONS_SYMBOL_NEXT_SYMBOL
	leay  	4,Y   			; 4 bytes per entry so skip this many to try next one 
	cmpy  	<tempPtr
	blo 	SEARCH_CONDITIONS_SYMBOL_CHECK_NEXT_SYMBOL
	; if here, no match was found
	lda  	#$FF  		; for unknown graphic?
	orcc 	#1
	puls  	B,Y,PC 

; ----------------------------------------------------
; compare a NULL terminated parameter pointed to by Y
; with a CR/SPACE/NULL terminated word pointed to by X
; This comparison is NOT case-sensitive!
; ---------------------------------------------------- 
COMPARE_PARAM
	pshs 	Y,X,D 
	clrb 
COMPARE_PARAM_NEXT_CHAR
	lda 	,Y+
	beq 	COMPARE_PARAM_CHECK_PASS
	bsr 	CONVERT_UPPERCASE
	sta 	<tempChar
	lda 	,X+
	bsr 	CONVERT_UPPERCASE
	cmpa 	<tempChar
	bne 	COMPARE_PARAM_FAIL
	decb 
	bne 	COMPARE_PARAM_NEXT_CHAR
	; if here, overflow. oh noes..
COMPARE_PARAM_FAIL
	orcc 	#1
	puls 	D,X,Y,PC 

COMPARE_PARAM_CHECK_PASS
	lda 	,X 
	beq 	COMPARE_PARAM_MATCH
	cmpa 	#C$CR 
	beq 	COMPARE_PARAM_MATCH
	cmpa 	#C$SPAC
	bne 	COMPARE_PARAM_FAIL
COMPARE_PARAM_MATCH
	andcc 	#$FE 
	puls 	D,X,Y,PC 

; -----------------------------------------------------------------------
; Entry: X = pointer to 2 character hex string representing a single byte
; Exit:  X = pointing to the character AFTER the last hex character 
; 	  A = binary equivalent of numbered converted 
; -----------------------------------------------------------------------
CONVERT_HEX_STRING_TO_BYTE
	lda 	,X+
	bsr 	CONVERT_UPPERCASE
	cmpa 	#'9'
	bls 	CONVERT_HEX_STRING_TO_BYTE_NOT_LETTER_1
	suba 	#7
CONVERT_HEX_STRING_TO_BYTE_NOT_LETTER_1
	suba 	#$30
	lsla 
	lsla 
	lsla 
	lsla
	sta 	<tempChar
	lda 	,X+
	bsr 	CONVERT_UPPERCASE
	cmpa 	#'9'
	bls 	CONVERT_HEX_STRING_TO_BYTE_NOT_LETTER_2
	suba 	#7
CONVERT_HEX_STRING_TO_BYTE_NOT_LETTER_2
	suba 	#$30
	ora 	<tempChar 
	rts


;---------------------------------
; convert to uppercase 
; Entry: A = character to be converted 
; Exit: A = converted character 
; --------------------------------
CONVERT_UPPERCASE
      ; check and/or convert lowercase to uppercase
      cmpa  #$61        ; $61 is "a"
      blo   CONVERT_UPPERCASE_NO_CONVERSION
      cmpa  #$7A  ; $7A is "z"
      bhi   CONVERT_UPPERCASE_NO_CONVERSION
      suba  #$20  ; convert from lowercase to uppercase 
CONVERT_UPPERCASE_NO_CONVERSION
      rts 

; --------------------------------------------------------------------------------
; copy a raw string, including control codes, etc until NULL 
; Entry: X = source pointer, Y = Destination Pointer 
; Exit: carry set = fail, carry clear success, Y = pointer to final NULL in dest 
; --------------------------------------------------------------------------------
STRING_COPY_RAW
	pshs 	X,D 
	clrb 
STRING_COPY_RAW_NEXT
	lda 	,X+
	sta 	,Y+
	beq 	STRING_COPY_RAW_DONE
	decb 
	bne 	STRING_COPY_RAW_NEXT
	coma 	; set carry for error 
	puls 	D,X,PC 

STRING_COPY_RAW_DONE
	leay 	-1,Y 		; undo auto-increment 
	; carry already cleared from STA of NULL 
	puls 	D,X,PC 

; ---------------------------------------------------------------------------------
; copy a CR-terminated string to destination 
; Entry: x = source, y = destination
; Exit: Y = pointining to null at the end of copy 
; ---------------------------------------------------------------------------------
STRING_COPY_CR
	pshs 	X,D 
	clrb 
STRING_COPY_CR_NEXT_CHAR
	lda 	,X+
	cmpa 	#C$CR
	beq 	STRING_COPY_CR_DONE
	sta 	,Y+
	decb 
	bne 	STRING_COPY_CR_NEXT_CHAR
	; if here, overflow 
	clr 	,Y 	; mark NULL in destination 
	coma 
	puls 	D,X,PC 
STRING_COPY_CR_DONE
	clr 	,Y 	; mark NULL in destination 
	puls 	D,X,PC 

; ---------------------------------------------
; Entry: A = path to write output to 
; ---------------------------------------------
PRINT_NULL_STRING
	pshs 	Y,X,D

PRINT_NULL_STRING_NEXT
	lda 	,X+
	bne 	PRINT_NULL_STRING_NEXT
	; found null terminator 
	tfr 	X,D 
	subd 	#1
	subd 	2,S
	tfr 	D,Y 
	ldx  	2,S 
	lda 	,S  			; grab path number off the stack  
	os9 	I$Write

	puls 	D,X,Y,PC 

; ------------------------------------------------------------------------------------
; print a string centered relative to the X xcoord specified (CANNOT use outputBuffer)
; Entry: A = x position to be centered AROUND
; 	   B = y position to print to
; 	   X = pointer to null-terminated string to print centered 
; ------------------------------------------------------------------------------------
PRINT_NULL_STRING_CENTER_RELATIVE
	pshs  Y,X,D 
 
	lda 	#$02 					; reposition text cursor code 
	sta 	outputBuffer,U
	leay 	outputBuffer+3,U 
PRINT_NULL_STRING_CENTER_RELATIVE_NEXT
	lda 	,X+
	sta 	,Y+
	bne 	PRINT_NULL_STRING_CENTER_RELATIVE_NEXT
	; found null terminator 
	tfr 	X,D 
	subd 	#1
	subd 	2,S
	std 	tempWord,U 
	; NOTE: assumes length will always be under 256 bytes 
	lsrb  					; divide by 2
	stb 	tempByte,U 
	ldd 	,S 
	suba 	tempByte,U 
	bcc 	PRINT_NULL_STRING_CENTER_RELATIVE_VALID_X
	; if here, the relative center is too far to left border so force 0 so we dont have negative value
	clra 
PRINT_NULL_STRING_CENTER_RELATIVE_VALID_X
	addd 	#$2020
	std 	outputBuffer+1,U 
	; now write the constructed locate command/string to gfx window
	lda 	gfxWindowPath,U
	leax 	outputBuffer,U 
	ldy 	tempWord,U 
	leay 	3,Y 			; add 3 bytes to the count to include the locate sequence 
	os9  	I$Write 

	puls 	D,X,Y,PC 

; ---------------------------------------------
; Entry: A = X cursor coordinate
;   	   B = Y cursor coordinate
;  	   X = pointer to null string to print
; ---------------------------------------------
PRINT_NULL_STRING_POSITION
	pshs 	Y,X,D

PRINT_NULL_STRING_POSITION_NEXT
	lda 	,X+
	bne 	PRINT_NULL_STRING_POSITION_NEXT
	; found null terminator 
	tfr 	X,D 
	subd 	#1
	subd 	2,S
	tfr 	D,Y 
	ldx  	2,S 
	lda 	,S  			; grab path number off the stack  
	os9 	I$Write

	puls 	D,X,Y,PC 


; -----------------------------------------------------------------------
; find NULL and return length 
; Entry: X = pointer to where to start measuring/looking 
; Exit: Y = length of characters until NULL 
; -----------------------------------------------------------------------
FIND_LEN_UNTIL_EOF 
	pshs 	X,A
	ldy 	#0
FIND_LEN_UNTIL_EOF_NEXT
	lda 	,X+
	beq 	FIND_LEN_UNTIL_EOF_END
	leay 	1,Y 
	bne 	FIND_LEN_UNTIL_EOF_NEXT
	orcc 	#1 	; set carry for overflow error
	puls 	A,X,PC 

FIND_LEN_UNTIL_EOF_END
	andcc 	#$FE
	puls 	A,X,PC 

; ----------------------------------------------------------------------
; change foreground text color
; Entry: A = foreground color to change to
; ----------------------------------------------------------------------
CHANGE_TEXT_COLOR
	pshs 	Y,X,D 

	sta 	fColorSequence+2,U 
	lda 	gfxWindowPath,U 
	leax 	fColorSequence,U 
	ldy 	#3
	os9  	I$Write 

	puls  	D,X,Y,PC 