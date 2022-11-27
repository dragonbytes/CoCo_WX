

; -------------------------------------------------------------------------------
; print a string of temperature digits in custom large
; 16x22 font
; Entry: X = pointer to null terminated string of digits (CANNOT be outputBuffer)
; 	  D = X coordinates to start
; 	  Y = Y coordinates to start 
; -------------------------------------------------------------------------------
PRINT_LARGE_DIGITS_STRING
	pshs 	Y,X,D 

	clr 	tempCounter,U
	leay 	outputBuffer,U 
	; init the X coordinate counter by saving to tempWord. Y coord is always constant so wrap-around WILL NOT WORK
	std 	tempWord,U 

PRINT_LARGE_DIGITS_STRING_NEXT
	lda  	,X+
	beq  	PRINT_LARGE_DIGITS_STRING_DONE
	cmpa 	#$20
	beq  	PRINT_LARGE_DIGITS_STRING_SPACE_CHAR
	cmpa  	#'+'
	beq  	PRINT_LARGE_DIGITS_STRING_NEXT  		; ignore plus sign in positive temps as its assumed if no minus sign
	cmpa  	#'-'
	bne  	PRINT_LARGE_DIGITS_STRING_NOT_MINUS
	lda  	#16
	bra   	PRINT_LARGE_DIGITS_STRING_NOT_DIGIT

PRINT_LARGE_DIGITS_STRING_SPACE_CHAR
	; for space characters, just skip over the width of a single character of 16 pixels 
	ldd  	tempWord,U 
	addd 	#16
	std  	tempWord,U 
	bra  	PRINT_LARGE_DIGITS_STRING_NEXT

PRINT_LARGE_DIGITS_STRING_NOT_MINUS
	cmpa 	<charDegreesSymbol
	bne  	PRINT_LARGE_DIGITS_STRING_NOT_DEGREES_SYMBOL
	lda  	#2
	ldb  	#8  						; pixel width to add to the "cursor" position
	bra  	PRINT_LARGE_DIGITS_STRING_NOT_DIGIT
	
PRINT_LARGE_DIGITS_STRING_NOT_DEGREES_SYMBOL
	cmpa  	#'F'
	bne   	PRINT_LARGE_DIGITS_STRING_NOT_FAHRENHEIT
	lda  	#15
	ldb  	#16  						; pixel width to add to the "cursor" position
	bra   	PRINT_LARGE_DIGITS_STRING_NOT_DIGIT

PRINT_LARGE_DIGITS_STRING_NOT_FAHRENHEIT
	cmpa  	#'C'
	bne  	PRINT_LARGE_DIGITS_STRING_NOT_CELSIUS
	lda   	#14
	ldb  	#16  						; pixel width to add to the "cursor" position
	bra   	PRINT_LARGE_DIGITS_STRING_NOT_DIGIT	

PRINT_LARGE_DIGITS_STRING_NOT_CELSIUS
	cmpa  	#'.'
	bne   	PRINT_LARGE_DIGITS_STRING_NOT_PERIOD
	lda  	#3
	ldb  	#6  						; pixel width to add to the "cursor" position
	bra   	PRINT_LARGE_DIGITS_STRING_NOT_DIGIT

PRINT_LARGE_DIGITS_STRING_NOT_PERIOD
	suba  	#$30  					; convert ascii number to value
	bcs  	PRINT_LARGE_DIGITS_STRING_DONE  	; something went wrong so just print what we have so far and exit
	cmpa  	#$09 			; make sure we didnt end up with some character beyond the 10 digits we have bitmaps for
	bhi 	PRINT_LARGE_DIGITS_STRING_DONE 	; something went wrong so just print what we have so far and exit
	; if here, we have a valid digit or symbol to render. now calculate the offset into the bitmapped buffers
	; by adding base buffer number of 2
 	adda 	#4  					; add 2 for start of buffers and 2 to skip degree/period
 	ldb  	#16  						; pixel width to add to the "cursor" position
PRINT_LARGE_DIGITS_STRING_NOT_DIGIT
 	sta 	tempByte,U 		; save it temporarily
 	stb  	pixelCharWidth,U 
 	; build the PutBlk sequence for a single digit and add to final outputBuffer
      	ldd 	#$1B2D 		; PutBlk sequence 
      	std 	,Y++
      	lda 	groupID,U 
      	ldb 	tempByte,U 
      	std 	,Y++
      	ldd 	tempWord,U  		; grab our current x coordinate position
      	std 	,Y++ 
    	addb  	pixelCharWidth,U
    	adca  	#0
      	std 	tempWord,U 
      	ldd 	4,S  			; always uses the y coordinate entry value off the stack
      	std 	,Y++

      	inc 	tempCounter,U 	; increment total number of characters we are gong to display at the end
      	bra  	PRINT_LARGE_DIGITS_STRING_NEXT

PRINT_LARGE_DIGITS_STRING_ERROR
	orcc 	#1  			; set carry for error and return without doing anything
	puls  	D,X,Y,PC 

PRINT_LARGE_DIGITS_STRING_DONE
	lda 	#8 			; 8 bytes per PutBlk sequence command 
	ldb  	tempCounter,U  	; total digits or symbols to display
	mul 
	; now send it all to the window path 
	tfr 	D,Y  
	lda 	gfxWindowPath,U 
	leax  	outputBuffer,U 
	os9 	I$Write 

	andcc 	#$FE 			; carry clear for success
	puls  	D,X,Y,PC 

; ----------------------------------------------------------------------------------------------------
; figure out the right wind diretion icon and then open gfx file, seek to it, and fill
; Get/Put buffer 20 with the right pixel data for it
; Entry: X = pointing to 1-3 character null-terminated wind direction string to load (N, NNW, SE, etc) 
; ----------------------------------------------------------------------------------------------------
LOAD_WIND_ICON
	pshs  	U,Y,X,D  

	clr  	<windIconIndex
	ldd  	,X++
	cmpd  	#$4E00  	; 'N' + null terminator
	beq  	LOAD_WIND_ICON_DONE
	cmpd  	#"NN"
	beq  	LOAD_WIND_ICON_DONE
	inc  	<windIconIndex
	cmpd  	#"NE"
	beq  	LOAD_WIND_ICON_DONE
	inc  	<windIconIndex
	cmpd  	#"EN"
	beq  	LOAD_WIND_ICON_DONE
	cmpd  	#$4500 	; 'E' + null
	beq  	LOAD_WIND_ICON_DONE
	cmpd  	#"ES"
	beq  	LOAD_WIND_ICON_DONE
	inc  	<windIconIndex
	cmpd  	#"SE"
	beq  	LOAD_WIND_ICON_DONE
	inc  	<windIconIndex
	cmpd  	#$5300  	; 'S' + null
	beq  	LOAD_WIND_ICON_DONE
	cmpd  	#"SS"
	beq  	LOAD_WIND_ICON_DONE
	inc  	<windIconIndex
	cmpd  	#"SW"
	beq  	LOAD_WIND_ICON_DONE
	inc  	<windIconIndex
	cmpa  	#'W' 	; ANY direction that starts with W will be W, WNW, or WSW which all translate to W
	beq   	LOAD_WIND_ICON_DONE
	inc  	<windIconIndex
	cmpd  	#"NW"
	beq  	LOAD_WIND_ICON_DONE
	; if here, it is an unknown value. return error
LOAD_WIND_ICON_ERROR	
	orcc 	#1
	puls  	D,X,Y,U,PC 

LOAD_WIND_ICON_DONE
      	; load the wind direction compass graphics from disk
      	lda  	#READ. 
      	clrb
      	leax  	gfxCompassFilename,PCR
      	os9  	I$Open 
      	bcs  	LOAD_WIND_ICON_ERROR
      	sta  	iconFilePath,U 
      	; seek to correct icon for corresponding wind direction in file
      	lda  	<windIconIndex
      	lsla 	; multiply index in A by 2 and clear B to give effective (windIconIndex * 512)
      	clrb 
	tfr  	D,U 
      	ldx  	#0
      	lda 	<iconFilePath
      	os9  	I$Seek 
      	ldu 	<uRegImage
      	; now setup GPBuffer and read in the pixel data
 	leax  	outputBuffer,U 
      	ldd 	#$1B2B 			; GPLoad sequence 
      	std 	,X++ 
      	lda 	groupID,U 
      	ldb 	#20  		; 20 = wind direction icon
      	std 	,X++
      	lda  	#8 				; screen type STY 
      	sta 	,X+ 
      	; block dimensions will be 32 pixels by 32 pixels 
      	ldd 	#32
      	std 	,X++
      	std  	,X++
      	ldd 	#512 		; in 16 color mode, 32x32 pixel block should be 512 bytes each 
      	std 	,X++ 
      	; read 512 bytes from file
      	lda 	iconFilePath,U     
      	ldy 	#512 				; copy data in 512 byte chunks 
      	os9  	I$Read 
      	bcs  	LOAD_WIND_ICON_ERROR
	; write the GPLoad start sequence to the gfx window
      	lda 	gfxWindowPath,U 
      	leax 	outputBuffer,U 
      	ldy 	#512+11  	; 512 bytes of pixel data + 11 for GPLoad sequence
      	os9  	I$Write 
      	bcs  	LOAD_WIND_ICON_ERROR
      	; if here, all went well. close path and report success!
      	lda  	<iconFilePath
      	os9  	I$Close 
      	
      	andcc 	#$FE 
      	puls  	D,X,Y,U,PC 

; -----------------------------------------------------------------------------------------
; open path to icons file and seek to matching icon's location for weather code (if exists)
; and then load it into a GET/PUT buffer for later use
; Entry: X = pointer to variable containing weatherCode to lookup (probably jsonWeatherCode)
; Exit: if everything works, GET/PUT has been loaded and carry and negative flags are clear
;       carry is set on any kind of disk access error
;       if jsonWeatherCode doesn't match with any known weather icon, carry clear but
;       negative flag is set
; -----------------------------------------------------------------------------------------
LOAD_WX_CONDITIONS_ICON
	pshs  	U,Y,X,D 

      	; now open path to icon image file
      	lda 	#READ. 
      	clrb 
      	leax 	gfxIconsFilename,PCR 
      	os9  	I$Open 
      	lbcs  	LOAD_WX_CONDITIONS_ICON_ERROR
      	sta 	iconFilePath,U 

      	; seek the file pointer to appropriate location for correct icon
      	ldx  	2,S  		; grab ptr to weatherCode off X on the stack
      	lbsr  	SEARCH_CONDITIONS_SYMBOL
      	lbcs 	LOAD_WX_CONDITIONS_ICON_NO_MATCH
      	; result should be in A. multiply it by 8 so we can use our * 256 trick  
      	lsla 
      	lsla 
      	lsla 
      	clrb 
      	tfr  	D,U 
      	ldx  	#0
      	lda 	<iconFilePath
      	os9  	I$Seek 
      	ldu 	<uRegImage
      	lbcs  	LOAD_WX_CONDITIONS_ICON_ERROR

      	leax  	outputBuffer,U 
      	ldd 	#$1B2B 			; GPLoad sequence 
      	std 	,X++ 
      	lda 	groupID,U 
      	ldb 	#1
      	std 	,X++
      	lda  	#8 				; screen type STY 
      	sta 	,X+ 
      	; block dimensions will be 64 pixels by 64 pixels 
      	ldd 	#64
      	std 	,X++
      	std  	,X++
      	ldd 	#2048 				; in 16 color mode, 64x64 pixel block should be 2k each 
      	std 	,X++ 
      	; write the GPLoad start sequence to the gfx window
      	lda 	gfxWindowPath,U 
      	leax 	outputBuffer,U 
      	ldy 	#11
      	os9  	I$Write 

      	lda 	iconFilePath,U 
      	leax 	outputBuffer,U 
      	ldy 	#512 				; copy data in 512 byte chunks 
      	os9  	I$Read 
      	bcs  	LOAD_WX_CONDITIONS_ICON_ERROR
      	lda 	gfxWindowPath,U 
      	ldy 	#512
      	os9  	I$Write 

      	lda 	iconFilePath,U 
      	ldy 	#512
      	os9  	I$Read 
      	bcs  	LOAD_WX_CONDITIONS_ICON_ERROR
      	lda 	gfxWindowPath,U 
      	ldy 	#512
      	os9  	I$Write 

      	lda 	iconFilePath,U 
      	ldy 	#512
      	os9  	I$Read 
      	bcs  	LOAD_WX_CONDITIONS_ICON_ERROR
      	lda 	gfxWindowPath,U 
      	ldy 	#512
      	os9  	I$Write 

      	lda 	iconFilePath,U 
      	leax 	outputBuffer,U 
      	ldy 	#512
      	os9  	I$Read 
      	bcs  	LOAD_WX_CONDITIONS_ICON_ERROR
      	lda 	gfxWindowPath,U 
      	ldy 	#512
      	os9  	I$Write 

      	lda 	iconFilePath,U 
      	os9  	I$Close 

      	clrb  	; clear carry flag
      	puls  	D,X,Y,U,PC   	

LOAD_WX_CONDITIONS_ICON_NO_MATCH
	clrb  		; clear carry flag since to disk access errors happened
	ldb  	#$80  	; set negative flag to show it couldnt find a matching icon for weather code
	puls  	D,X,Y,U,PC 

LOAD_WX_CONDITIONS_ICON_ERROR
	comb  	; set carry flag for error 
	puls  	D,X,Y,U,PC 

; ---------------------------------------------------------------------
LOAD_ALL_GFX_DIGITS
	pshs  	U,Y,X,D 

      	lda  	#READ.
      	clrb 
      	leax  	gfxDigitsFilename,PCR 
      	os9  	I$Open 
      	lbcs 	LOAD_ALL_GFX_DIGITS_ERROR
      	sta 	digitGfxPath,U 

 	leax  	outputBuffer,U 
      	ldd 	#$1B2B 			; GPLoad sequence 
      	std 	,X++ 
      	lda 	groupID,U 
      	ldb 	#2
      	std 	,X++
      	lda  	#8 				; screen type STY 
      	sta 	,X+ 
      	; first object to load is degree symbol which is 8x22
      	ldd 	#8
      	std 	,X++
      	ldd 	#22
      	std  	,X++
      	ldd 	#88 				; in 16 color mode 
      	std 	,X++ 
      	lda  	digitGfxPath,U 
      	leax  	outputBuffer+11,U 
      	ldy 	#88
      	os9  	I$Read	
      	lbcs   	LOAD_ALL_GFX_DIGITS_ERROR
  	; send the GPLoad sequence to import it in 
      	lda 	gfxWindowPath,U 
      	leax  	outputBuffer,U 
      	ldy  	#99  				; 44 bytes for 4x22 pixel graphic + 11 for GPLoad command stuff
      	os9  	I$Write 

      	inc  	outputBuffer+3,U 		; increment to the next get/put buffer number 
      	; now setup the GPLoad parameters for period, which is 6x22
      	ldd 	#6
      	std 	outputBuffer+5,U 
      	ldd 	#66 				; in 16 color mode 
      	std 	outputBuffer+9,U 
      	lda  	digitGfxPath,U 
      	leax  	outputBuffer+11,U 
      	ldy 	#66
      	os9  	I$Read	
      	bcs  	LOAD_ALL_GFX_DIGITS_ERROR
  	; send the GPLoad sequence to import it in 
      	lda 	gfxWindowPath,U 
      	leax  	outputBuffer,U 
      	ldy  	#77  				; 66 bytes for 6x22 pixel graphic + 11 for GPLoad command stuff
      	os9  	I$Write 

      	inc  	outputBuffer+3,U 		; increment to the next get/put buffer number 
      	; reset the outputBuffer "header" for 16x22 pixels at 176 bytes each 
      	ldd 	#16
      	std  	outputBuffer+5,U 
      	ldd 	#176 
      	std 	outputBuffer+9,U 
      	; setup counter for '/' symbol, digits, degree, 'F' and 'C'
      	ldb 	#15
      	stb 	tempByte,U 
LOAD_ALL_GFX_DIGITS_NEXT
      	lda 	digitGfxPath,U 
      	leax  	outputBuffer+11,U 
      	ldy 	#176
      	os9  	I$Read 
      	bcs  	LOAD_ALL_GFX_DIGITS_ERROR
      	; send the GPLoad sequence to import it in 
      	lda 	gfxWindowPath,U 
      	leax  	outputBuffer,U 
      	ldy  	#187  				; 176 bytes for 16x22 pixel graphic + 11 for GPLoad command stuff
      	os9  	I$Write 

      	inc  	outputBuffer+3,U 
      	dec  	tempByte,U 
      	bne  	LOAD_ALL_GFX_DIGITS_NEXT

      	lda  	digitGfxPath,U 
      	os9  	I$Close 

      	andcc 	#$FE 	; clear carry
      	puls  	D,X,Y,U,PC 

LOAD_ALL_GFX_DIGITS_ERROR
	orcc 	#1
	puls  	D,X,Y,U,PC