**************************************************************************************************
* CoCo WX 2.1 - Written By Todd Wallace
*
* So I am a bit of a weather geek. I even have my own outdoor wireless sensor that can measure 
* wind speed, direction, rainfall, etc. Weather "apps" are available on almost every platform
* capable of connecting to the internet, so how cool would it be to do it on a CoCo too? Well I 
* found this cool web-based poweruser-oriented online weather service called wttr.in. It's 
* free to use and has a very simple implementation. I figured out how to do a simple HTTP 
* request over a TCP connection made with DriveWire's virtual serial port drivers and voila!
*
* New In Versin 2.1
* - better handling of HTTP server error responses
* - better detection of locations that arent found in the search
* - proper support for spaces in the location name
*
* New in Version 2.0
*
* I have completely rewritten the networking parts of the code to request and parse weather data
* in JSON format from wttr.in as that medium contains a much wider range of data and units of
* measure. This now lets the user view their weather data in either metric or imperial measurements
* regardless of the region they are checking the conditions of.
*
* The biggest change you'll actually notice is the new default full-color graphical output mode
* with icons and everything! 
**************************************************************************************************

; Definitions/equates 
STDOUT      			EQU   1
STDIN 				EQU   0
H6309    			set   1

cr_lf 				EQU 	$0D0A 

network_signal 		EQU 	32
keyboard_signal 		EQU 	33
connect_timeout_signal	EQU 	$88
wx_refresh_signal  		EQU  	$80

;graphics_display 		EQU 	1
;wttr_down 			EQU  	1

	include 	os9.d
	include 	rbf.d
	include 	scf.d 

	pragma 	cescapes

; Module header setup info 
	MOD 	MODULE_SIZE,moduleName,$11,$80,START_EXEC,data_size

START_MODULE
**************************************************************************************
; -----------------------------------------------------
; Variables 
		org 	0

uRegImage   		RMB 	2
networkPath 		RMB 	1
gfxWindowPath 	RMB 	1
digitGfxPath  	RMB  	1
nilPath 		RMB 	1
iconFilePath  	RMB 	1
gfxStatusPath  	RMB  	1
networkDataReady 	RMB 	1
pendingConnect 	RMB 	1
abortFlag 		RMB 	1
networkTimeoutFlag 	RMB 	1
keyInputFlag  	RMB  	1
contentLengthFlag  	RMB  	1
copyContentFlag  	RMB  	1
groupID  		RMB 	1
outputMode  		RMB  	1
fColorSequence  	RMB 	3
windIconIndex  	RMB  	1
metricOutputFlag  	RMB  	1
refreshFlag  		RMB 	1
wxRefreshFlag 	RMB  	1

networkBufferEndPtr 	RMB 	2
replyBufferCurPtr 	RMB  	2
replyBufferEndPtr 	RMB 	2
contentBodyPtr  	RMB  	2
jsonCurCondPtr  	RMB  	2
shellParamPtr 	RMB 	2
searchEndPtr  	RMB  	2
dwReadBytes  		RMB  	2
tempPtr 		RMB 	2
tempChar 		RMB 	1
tempByte 		RMB 	1
tempWord 		RMB 	2
tempCounter  		RMB 	1
charDegreesSymbol 	RMB 	1
pixelCharWidth 	RMB 	1
jsonTableCounter 	RMB  	1
strHexWord   		RMB  	10
u8Value 		RMB  	1
debugFlag   		RMB  	1
contentLength  	RMB  	2
constContentLength  	RMB  	2
hpaValue   		RMB  	2
u32Value  		RMB  	4
; inHg pressure conversion variables
v24h  			RMB 	1
v24m  			RMB  	1
v24l  			RMB  	1
pressureInches  	RMB  	6

pdBuffer 		RMB 	32

networkBuffer 	RMB 	256
networkBufferSz	EQU 	.-networkBuffer 
outputBuffer 		RMB 	512

replyBuffer  		RMB  	4096

; json variables 
jsonFeelsLikeC  	RMB  	5
jsonFeelsLikeF  	RMB  	5
jsonHumidity  	RMB  	4
jsonLocalTime  	RMB  	21
jsonObsTime  		RMB  	10
jsonPrecipInches  	RMB  	5
jsonPrecipMM  	RMB  	5
jsonPressure 		RMB  	6
jsonTempC   		RMB  	5
jsonTempF  		RMB  	5
jsonWeatherCode  	RMB  	5
jsonWindDir 		RMB  	4
jsonWindSpeedKPH 	RMB 	4
jsonWindSpeedMPH  	RMB  	4
jsonWeatherDesc  	RMB  	32
jsonAreaName   	RMB  	20
jsonRegion  		RMB  	20 

stringBuffer  	RMB  	64
gfxWindDir   		RMB  	3

; End of Variables
; -----------------------------------------------------
; YOU MUST RESERVE SOME SPACE FOR STACK HERE
stackSpace		RMB  	128
data_size         	EQU   .
; -----------------------------------------------------
; Constants
moduleName   		FCS 	"cocowx"
networkPathName	FCS 	"/N"
winPathName 		FCC 	"/W\r"
nilPathName		FCC 	"/NIL\r"
gfxIconsFilename  	FCC 	"/dd/sys/cocowx/wx_icons.bin\r"
gfxDigitsFilename	FCC 	"/dd/sys/cocowx/wx_digits.bin\r"
gfxCompassFilename  	FCC  	"/dd/sys/cocowx/wx_compass.bin\r"

dwSelectSequence	FCB  	$1B,$21

dwSetWindow  		FCB 	$1B,$20,8,0,0,40,25,2,0,0
			FCB 	$1B,$35,0 		; disable scaling of coords
			; setup palette colors
			FCB 	$1B,$31,0,0
			FCB 	$1B,$31,1,53  	; orange for sun edges
			FCB 	$1B,$31,2,11 		; darker blue color for rain and dark clouds
			FCB 	$1B,$31,3,25  	; light blue for regular clouds 
			FCB 	$1B,$31,4,7 		; dark gray for cloud edges
			FCB 	$1B,$31,5,54 		; yellow sun color 
			FCB 	$1B,$31,6,56 		; light gray for light clouds
			FCB 	$1B,$31,7,63 		; white text 
			FCB 	$1B,$31,8,27  	; cyan blue for snow flakes and sleet
			FCB  	$1B,$31,9,36   	; red for wind compass indicator
			FCB  	$1B,$31,10,16  	; green for text
			FCB  	$1B,$31,11,29
			FCB  	$1B,$31,12,31
			; turn off the text cursor
			FCB  	$05,$20
dwSetWindowSz 	EQU 	*-dwSetWindow
; (make sure to use NULL at end)
selectFontTitle 	FCB 	$1B,$3A,$C8,$42,0
selectFontInfo 	FCB 	$1B,$3A,$C8,$02,0  	; $02 = standard narrow font, $32 = Mac narrow font (no degrees)
selectFontAuthor 	FCB  	$1B,$3A,$C8,$09,0

infoColorSequence  	FCB  	$1B,$32,11,0 		; 0 at end is null terminator
labelColorSequence  	FCB 	$1B,$32,7,0  		; 0 at end is null terminator

screenUpdateSeq 	FDB  	$1B40,0,40  		; move draw pointer
			FCB  	$1B,$32,0  		; select black color
			FDB 	$1B4A,319,199  	; draw a solid bar rectangle to blank out most of the screen
screenUpdateSeqSz  	EQU  	*-screenUpdateSeq

strTitle 		FCN 	"CoCo WX v2.1 - Written by Todd Wallace\r\n\n"
strUsage		FCC 	"Check live weather conditions for anywhere in the world using your CoCo! This\r\n"
			FCC 	"tool works by leveraging DriveWire (required) and the online weather info and\r\n"
			FCC 	"forecasting service wttr.in to request and retrieve live data.\r\n\n"
			FCC 	"Usage: cocowx [-t [-d hex_value]] [-m] <location>\r\n\n"
			FCC 	" - New in version 2.0 is a fully graphical output mode, complete with full-color"
			FCC 	"   icons! This mode is now the default, however the traditional text-only output"
			FCC 	"   can still be used by including the -t flag.\r\n"
			FCC 	" - When using the text-only mode, you can also optionally add the -d flag to\r\n"
			FCC 	"   customize the degrees symbol character displayed. This is to accommodate\r\n"
			FCC 	"   other OS-9 fonts with a different character set. The value must be expressed\r\n"
			FCC 	"   as a 2-character hexadecimal ASCII code. (Example: cocowx -t -d F8)\r\n"
			FCC  	" - To display values in Metric units instead of Imperial (which is the default)\r\n"
			FCC  	"   use the optional -m flag.\r\n"
			FCC 	" - The location parameter can be in a wide range of formats like city and state,"
			FCC 	"   city by itself, zipcode, etc. See http://wttr.in/help for more details.\r\n"
			FCC 	" - In graphics mode, the weather info will be auto-updated every 10 minutes,\r\n"
			FCC  	"   but you can request a manual refresh at any time by pressing the ENTER key.\r\n"
strUsageSz 		EQU 	*-strUsage

strConnecting		FCN 	"Connecting... "
strConnectSuccess 	FCN  	"Success\r\nRequesting weather data... "
strDone 		FCN  	"Done\r\n"
strMsgLoadingGfx  	FCN  	"Loading graphics from disk... "
strGfxRetrieving  	FCN  	"     Updating WX Data: Requesting..."
strGfxTimeout  	FCN  	"         Error: Network Timeout"
strGfxConnecting  	FCN  	"     Updating WX Data: Connecting..."

strConnect 		FCC 	"TCP CONNECT wttr.in 80\r"
strConnectSz 		EQU 	*-strConnect

strUserAborted 	FCN 	"\x03\rUser aborted.\r\n"

strGetPrefix 		FCN 	"GET /"
strGetSuffix 		FCN 	" HTTP/1.1\r\n"
strHostInfo 		FCN 	"Host: wttr.in\r\n"
strUserAgent 		FCN 	"User-Agent: curl/7.68.0\r\n\r\n"
;strWeatherFormatTxt 	FCN 	"?format=TANDY%l\\n%C\\n%x\\n%t\\n%f\\n%h\\n%P\\n%w\\n%p\\n%m\\n%S\\n%s\\n"
strWeatherFormatTxt 	FCN  	"?format=j2"
;strWeatherFormatTxt 	FCN  	"?T2n"
;strGetConnection  	FCN  	"Connection: keep-alive\r\n"

strConnectFailed 	FCN 	"\x03\rCould not connect to server ("

strKEYWORDok 		FCN 	"OK "
strKEYWORDfail 	FCN 	"FAIL "
strKEYWORDcontent  	FCN 	"CONTENT-LENGTH: "
strKEYWORDtong  	FCN  	"TONG"
strKEYWORDhttp1.1  	FCN  	"HTTP/1.1"
strKEYWORDdoubleCRLF FCB  	$0D,$0A,$0D,$0A,0

; json keywords and variable pointers
jsonKeywordCurCond  	FCN  	"current_condition"
strJSONfeelsLikeC 	FCN  	"FeelsLikeC"
strJSONfeelsLikeF 	FCN  	"FeelsLikeF"
strJSONhumidity 	FCN 	"humidity"
strJSONlocalTime 	FCN 	"localObsDateTime"
strJSONobsTime  	FCN 	"observation_time"
strJSONprecpInches 	FCN  	"precipInches"
strJSONprecipMM 	FCN  	"precipMM"
strJSONpressure  	FCN  	"pressure" 		; in hPa
strJSONtemp_C  	FCN 	"temp_C"
strJSONtemp_F  	FCN  	"temp_F"
strJSONweatherCode 	FCN 	"weatherCode"
strJSONwindDir  	FCN  	"winddir16Point"
strJSONwindSpeedKPH 	FCN 	"windspeedKmph"
strJSONwindSpeedMPH 	FCN 	"windspeedMiles"
; these keywords are for use with sub-parameters
strJSONweatherDesc  	FCN  	"weatherDesc"
strJSONvalue  	FCN 	"value"

strJSONnearestArea 	FCN 	"nearest_area"
strJSONareaName   	FCN 	"areaName"
strJSONregion  	FCN  	"region"

jsonKeywordVarsTable FDB  	strJSONfeelsLikeC   	; source keyword to find
			FDB  	jsonFeelsLikeC 	; destination for string to be copied to
			FDB  	strJSONfeelsLikeF
			FDB  	jsonFeelsLikeF
			FDB 	strJSONhumidity
			FDB  	jsonHumidity
			FDB  	strJSONlocalTime
			FDB  	jsonLocalTime 
			FDB  	strJSONobsTime
			FDB  	jsonObsTime 
			FDB  	strJSONprecpInches
			FDB  	jsonPrecipInches
			FDB  	strJSONprecipMM
			FDB  	jsonPrecipMM 
			FDB 	strJSONpressure
			FDB  	jsonPressure 
			FDB  	strJSONtemp_C
			FDB  	jsonTempC   		
			FDB  	strJSONtemp_F   
			FDB  	jsonTempF 
			FDB  	strJSONweatherCode
			FDB  	jsonWeatherCode 
			FDB  	strJSONwindDir
			FDB  	jsonWindDir
			FDB  	strJSONwindSpeedKPH
			FDB  	jsonWindSpeedKPH
			FDB  	strJSONwindSpeedMPH
			FDB  	jsonWindSpeedMPH 
json_keyword_vars_sz EQU  	(*-jsonKeywordVarsTable)/4  ; 2 bytes per ptr, 2 ptrs per entry = 4

 IFDEF wttr_down
; DEBUG REASONS
XjsonTempF  		FCN 	"68"
XjsonFeelsLikeF  	FCN  	"65"
XjsonHumidity  	FCN  	"51"
XjsonLocalTime   	FCN  	"2022-04-24 01:15 PM"
XjsonPrecipInches  	FCN  	"0.0"
XjsonPressure  	FCN  	"1028"
XjsonWeatherCode  	FCN  	"116"
XjsonWindDir  	FCN  	"NE"
XjsonWindSpeedMPH 	FCN  	"19"
XjsonWeatherDesc  	FCN 	"Partly cloudy"
XjsonAreaName  	FCN  	"Providence"
XjsonRegion  		FCN  	"Rhode Island"
 ENDC 

strBlank  		FCN  	""

testBufferSeq  	FCB  	$1B,$2D,3,2
			FDB  	0,0 

bin32dec1M 		FQB 	1000000 		; 1 million decimal 
bin32dec100K 		FQB 	100000 		; 100 thousand decimal 
bin32dec10K 		FQB 	10000 	

strCurrentWeather 	FCN 	"Current weather for "
strLocation  		FCN 	"WEST WARWICK, RI"

strTemperature 	FCN 	"\r\n\nTemperature: "
strFeelsLike 		FCN 	", Feels Like: "
strHumidity 		FCN 	", Humidity: "
strPressure 		FCN 	", Pressure: "
strWind 		FCN 	"\r\nWind: "
strPrecipitation 	FCN 	", Rainfall: "
strMoonPhase 		FCN 	", Moon Phase: "
strSunrise 		FCN 	"\r\nSunrise: "
strSunset 		FCN 	", Sunset: "
strTimeLocal 		FCN 	" (Times All Local)"
strDateTime  		FCN  	", Observation Time: "
strWindMPH   		FCN  	" mph"
strWindKPH  		FCN  	" kph"
strPressureInHg  	FCN  	" inHg"
strPressurehPa  	FCN  	" hPa"
strForecast  		FCN  	"\r\n\n3-Day Forecast: "
strForecastHighLow 	FCN  	"                "


strPartlyCloudy 	FCN 	"Partly Cloudy"
strLightSnowShowers 	FCN 	"Light Snow Showers"
strGfxCoCoWX 		FCN 	"CoCo WX v2.1"
strGfxAuthor  	FCN  	"Written by Todd Wallace"
strGfxFeelsLike  	FCN  	"Feels Like: "
strGfxHumidity	FCN   	"Humidity: "
strGfxPressure   	FCN  	"Pressure: "
strGfxWind  		FCN  	"Wind"
strGfxObsTime  	FCN  	"Observation Time: "
strGfxRainfall  	FCN  	"Rainfall: "

; conditions weather code table (has to be 4 bytes per entry)
curCondCodeTable 	EQU 	*
symCloudy	 	FCC 	"119" 		; Cloudy
			FCB 	0
symFog1		FCC 	"143" 		; Fog
			FCB 	1
symFog2		FCC 	"248" 		; Fog (duplicate with different number)
			FCB 	1
symFog3		FCC 	"260" 		; Fog (duplicate with different number)
			FCB 	1
symHeavyRain1		FCC 	"302" 		; HeavyRain
			FCB 	2
symHeavyRain2		FCC 	"308" 		; HeavyRain
			FCB 	2
symHeavyRain3		FCC 	"359" 		; HeavyRain
			FCB 	2
symHeavyShowers1	FCC 	"299" 		; HeavyShowers
			FCB 	6
symHeavyShowers2	FCC 	"305" 		; HeavyShowers
			FCB 	6
symHeavyShowers3	FCC 	"356" 		; HeavyShowers
			FCB 	6
symHeavySnow1		FCC 	"230" 		; HeavySnow
			FCB 	4
symHeavySnow2		FCC 	"329" 		; HeavySnow
			FCB 	4
symHeavySnow3		FCC 	"332" 		; HeavySnow
			FCB 	4
symHeavySnow4		FCC 	"338" 		; HeavySnow
			FCB 	4
symHeavySnowShowers1	FCC 	"335" 		; HeavySnowShowers
			FCB 	5
symHeavySnowShowers2	FCC 	"371" 		; HeavySnowShowers
			FCB 	5
symHeavySnowShowers3	FCC 	"395" 		; HeavySnowShowers
			FCB 	5
symLightRain1		FCC 	"266" 		; LightRain1
			FCB 	3
symLightRain2		FCC 	"293" 		; LightRain2
			FCB 	3
symLightRain3		FCC 	"296" 		; LightRain3
			FCB 	3
symLightShowers1	FCC 	"176" 		; LightShowers1
			FCB 	6
symLightShowers2	FCC 	"263" 		; LightShowers2
			FCB 	6
symLightShowers3	FCC 	"353" 		; LightShowers3
			FCB 	6
symLightSleet1	FCC 	"182" 		; LightSleet1
			FCB 	8
symLightSleet2	FCC 	"185" 		; LightSleet2 
			FCB 	8
symLightSleet3	FCC 	"281" 		; LightSleet3 
			FCB 	8
symLightSleet4	FCC 	"284" 		; LightSleet4 
			FCB 	8
symLightSleet5	FCC 	"311" 		; LightSleet5 
			FCB 	8
symLightSleet6	FCC 	"314" 		; LightSleet6 
			FCB 	8
symLightSleet7	FCC 	"317" 		; LightSleet7 
			FCB 	8
symLightSleet8	FCC 	"350" 		; LightSleet8 
			FCB 	8
symLightSleet9	FCC 	"377" 		; LightSleet9 
			FCB 	8
symLightSleetShwrs1 	FCC 	"179" 		; LightSleetShowers
			FCB 	8
symLightSleetShwrs2 	FCC 	"362" 		; LightSleetShowers
			FCB 	8
symLightSleetShwrs3 	FCC 	"365" 		; LightSleetShowers
			FCB 	8
symLightSleetShwrs4 	FCC 	"374" 		; LightSleetShowers
			FCB 	8
symLightSnow1		FCC 	"227" 		; LightSnow
			FCB 	7
symLightSnow2		FCC 	"320" 		; LightSnow
			FCB 	7
symLightSnowShowers1	FCC 	"323" 		; LightSnowShowers
			FCB  	5
symLightSnowShowers2	FCC 	"326" 		; LightSnowShowers
			FCB  	5
symLightSnowShowers3	FCC 	"368" 		; LightSnowShowers
			FCB  	5
symPartlyCloudy	FCC 	"116" 		; PartlyCloudy
			FCB 	9
symSunny		FCC 	"113"  	; Sunny
			FCB  	10
symThunderHeavyRain	FCC 	"389" 		; ThunderyHeavyRain
			FCB 	13
symThunderShowers1	FCC 	"200" 		; ThunderyShowers1
			FCB  	11
symThunderShowers2	FCC 	"386" 		; ThunderyShowers2
			FCB  	11
symThunderSnowShwrs	FCC 	"392" 		; ThunderySnowShowers
			FCB 	5
symVeryCloudy		FCC 	"122"		; VeryCloudy
			FCB 	12
curCondCodeTableEnd	EQU  	*

moonphaseTable 	FDB 	strMoonNew
			FDB 	strMoonWaxCrescent
			FDB 	strMoonFirstQuarter
			FDB 	strMoonWaxGibbous
			FDB 	strMoonFull
			FDB 	strMoonWanGibbous
			FDB 	strMoonLastQuarter
			FDB 	strMoonWanCrescent

; moonphase string descriptions
strMoonNew 		FCN 	"New Moon"
strMoonWaxCrescent 	FCN 	"Waxing Crescent"
strMoonFirstQuarter 	FCN 	"First Quarter"
strMoonWaxGibbous 	FCN 	"Waxing Gibbous"
strMoonFull 		FCN 	"Full Moon"
strMoonWanGibbous 	FCN 	"Waning Gibbous"
strMoonLastQuarter 	FCN 	"Last Quarter"
strMoonWanCrescent 	FCN 	"Waning Crescent"

strErrorInvalidParam FCN 	"Invalid parameters or syntax. Type COCOWX by itself to see usage information.\r\n"
strErrorInvalidFlag 	FCN 	"Invalid flag. Type COCOWX by itself to see usage information.\r\n"
strErrorNoDrivewire 	FCN 	"Error opening path to DriveWire Virtual Serial Port module /N.\r\nIs DriveWire installed correctly?\r\n"
strErrorVRNmodule 	FCN 	"Error opening path to /NIL module which is needed for connection timeout timer\r\nto function. Otherwise you will have to manually exit by pressing ESC.\r\n"
strErrorTimeout 	FCN 	"\x03\rError communicating with the wttr.in weather service. Connection either timed\r\nout or didn't responded to the request as expected. Is your DriveWire server\r\nconnected to the internet? Try visiting https://wttr.in from it to make sure the service is working and not having an outage.\r\n"
strErrorGraphics  	FCN  	"Graphics files not found. Exiting...\r\n"
strErrorLocation  	FCN  	"Location not found ("
strErrorServerReply 	FCN  	"Unexpected server reply ("

asciiHexList	FCC 	"0123456789ABCDEF"
; -----------------------------------------------------

START_EXEC
**************************************************************************************
* Program code area 
* RULE #1 - USE U TO REFERENCE ANY CHANGEABLE VARIABLES IN THE DATA AREA.
* RULE #2 - USE PCR TO REFERENCE CONSTANTS SINCE THEY RESIDE WITH EXECUTABLE CODE.
* RULE #3 - NEVER USE JSR FOR CALLING SUBROUTINES. ALWAYS USE BSR OR LBSR INSTEAD.
**************************************************************************************

      	stu   	<uRegImage        ; save copy of data area pointer in U 
      	stx 	<shellParamPtr

      	ldd 	#$1B32 
      	std 	fColorSequence,U 

      ;	lbra  	DEBUG_BYPASS
      ; init path variables
      lda  	#$FF 
      sta  	<gfxWindowPath
      sta  	<iconFilePath
      sta 	<networkPath
      sta  	<nilPath
      sta  	<digitGfxPath

      clra 
      sta   	<debugFlag
      sta  	<metricOutputFlag  	; imperial units is the default so set metric to 0
      sta 	<keyInputFlag
      sta  	<refreshFlag
      sta  	<wxRefreshFlag

      	; display title/author info 
	leax 	strTitle,PCR 
	lda 	#STDOUT 
	lbsr 	PRINT_NULL_STRING

      	; set default char for degree symbol 
      	lda 	#$BE 			; value for GIME text-mode screen types 
      	sta 	<charDegreesSymbol
      	clr 	<outputMode   	; set default output mode to graphics (any non-zero means text-only)

	ldx 	<shellParamPtr
      	lbsr 	FIND_NEXT_NONSPACE_CHAR
      	cmpa 	#C$CR
      	lbeq 	DISPLAY_INFO_USAGE
FLAGS_SEARCH_NEXT
	; check if we have a flag 
	lda  	,X+ 
	cmpa  	#C$CR  
	lbeq 	ERROR_INVALID_PARAMS  	; missing city/state/location which is required
      	cmpa 	#'-'
      	bne 	NO_MORE_FLAGS
      	lda 	,X+
      	; check for degree symbol character flag 
      	lbsr 	CONVERT_UPPERCASE
      	cmpa 	#'D'
      	bne  	FLAGS_CHECK_TEXT_ONLY
      	lbsr 	FIND_NEXT_NONSPACE_CHAR
      	cmpa 	#C$CR 
      	lbeq 	ERROR_INVALID_PARAMS
      	lbsr 	CONVERT_HEX_STRING_TO_BYTE 		; convert the 2 character hex into a binary byte value 
      	sta 	<charDegreesSymbol
      	lbsr 	FIND_NEXT_NONSPACE_CHAR
      	bra   	FLAGS_SEARCH_NEXT

FLAGS_CHECK_TEXT_ONLY
	cmpa  	#'T'
	bne  	FLAGS_CHECK_METRIC
	lda  	,X+ 
	cmpa  	#C$SPAC 
	lbne 	ERROR_INVALID_PARAMS
	sta  	<outputMode   	; any value non-zero will force text-only output
	lbsr 	FIND_NEXT_NONSPACE_CHAR
	bra   	FLAGS_SEARCH_NEXT

FLAGS_CHECK_METRIC
	cmpa  	#'M'
	lbne  	ERROR_UNKNOWN_FLAG
	lda  	,X+
	cmpa  	#C$SPAC 
	lbne 	ERROR_INVALID_PARAMS
	sta   	<metricOutputFlag 	; any value non-zero will select metric units output
	lbsr 	FIND_NEXT_NONSPACE_CHAR
	bra   	FLAGS_SEARCH_NEXT

NO_MORE_FLAGS
	leax  	-1,X  		; undo auto-increment 
	stx 	<shellParamPtr

; FOR TESTING WHEN WTTR.IN IS DOWN
 IFDEF wttr_down
 	leay  	jsonTempF,U 
 	leax  	XjsonTempF,PCR 
 	lbsr  	STRING_COPY_RAW
 	leay 	jsonFeelsLikeF,U 
 	leax  	XjsonFeelsLikeF,PCR 
 	lbsr  	STRING_COPY_RAW
 	leay  	jsonHumidity,U 
 	leax  	XjsonHumidity,PCR 
 	lbsr  	STRING_COPY_RAW
  	leay  	jsonPressure,U 
 	leax  	XjsonPressure,PCR 
 	lbsr  	STRING_COPY_RAW
  	leay  	jsonPrecipInches,U 
 	leax  	XjsonPrecipInches,PCR 
 	lbsr  	STRING_COPY_RAW
  	leay  	jsonWindDir,U 
 	leax  	XjsonWindDir,PCR 
 	lbsr  	STRING_COPY_RAW
  	leay  	jsonWindSpeedMPH,U 
 	leax  	XjsonWindSpeedMPH,PCR 
 	lbsr  	STRING_COPY_RAW
  	leay  	jsonLocalTime,U 
 	leax  	XjsonLocalTime,PCR 
 	lbsr  	STRING_COPY_RAW
  	leay  	jsonWeatherDesc,U 
 	leax  	XjsonWeatherDesc,PCR 
 	lbsr  	STRING_COPY_RAW
  	leay  	jsonWeatherCode,U 
 	leax  	XjsonWeatherCode,PCR 
 	lbsr  	STRING_COPY_RAW
  	leay  	jsonAreaName,U 
 	leax  	XjsonAreaName,PCR
  	lbsr  	STRING_COPY_RAW
  	leay  	jsonRegion,U 
 	leax  	XjsonRegion,PCR 
 	lbsr  	STRING_COPY_RAW

 	lbra  	DEBUG_WTTR_DOWN
 ENDC

 	lda  	<nilPath
 	bpl  	VRN_PATH_ALREADY_OPEN
      	; setup path to VRN driver for timer functionality for connection timeout  
 	lda 	#UPDAT.
 	clrb 
 	leax 	nilPathName,PCR 
 	os9 	I$Open 
 	bcc 	GOT_VRN_PATH
 	; tell user vrn is needed for the timeout timer to work 
 	leax 	strErrorVRNmodule,PCR
 	lda 	#STDOUT 
 	lbsr 	PRINT_NULL_STRING
 	lda 	#$FF 		; this makes sure bit 7 is set so we know there is no VRN 
GOT_VRN_PATH
 	sta 	<nilPath
VRN_PATH_ALREADY_OPEN

SETUP_REFRESH_WEATHER_REQUEST
      	ldd 	#0
      	sta 	<networkDataReady
      	sta 	<pendingConnect
      	sta 	<abortFlag
      	sta 	<networkTimeoutFlag
 
      	leax  	replyBuffer,U 
      	stx  	<replyBufferEndPtr

      	lda  	<refreshFlag
      	bne  	SKIP_SIGNAL_HANDLER_SETUP
      	; setup the intercept stuff if not already configured
      	leax 	SIGNAL_HANDLER,PCR
      	os9 	F$Icpt

SKIP_SIGNAL_HANDLER_SETUP
      	lbsr 	DRIVEWIRE_SETUP
      	lbcs 	ERROR_NO_DRIVEWIRE

      	; send the connect command to drivewire to connect to wttr.in web server 
	lda 	<networkPath
	leax 	strConnect,PCR 
	ldy 	#strConnectSz
	os9 	I$Write      
	inc 	<pendingConnect 	

      	; setup timeout timer where if it cant connect or HTTP GET request timesout, we can gracefully fail. 
	lda 	<nilPath
	ldb 	#SS.FSet  	; code $C7
	ldx 	#900 		; 15 seconds 
	ldy 	#0
	ldu 	#connect_timeout_signal
	os9 	I$SetStt 
	ldu 	<uRegImage

	; tell the user we are trying to connect and sending the request to server if successful 
	lda 	<refreshFlag
	bne  	MAINLOOP  		; skip STDOUT message since we are in graphics mode
	lda 	#STDOUT 
	leax 	strConnecting,PCR 
	lbsr 	PRINT_NULL_STRING
MAINLOOP
	lda  	<networkDataReady
	bne  	MAINLOOP_NEXT_READ
	lda  	<keyInputFlag
	bne  	MAINLOOP_NEW_KEYSTROKES
	lda  	<wxRefreshFlag
	lbne 	REFRESH_WEATHER_DATA  	; the refresh timer elapsed and its time to refresh wx data/display it
	lda  	<abortFlag
	lbne  	USER_ABORT_EXIT
	lda  	<networkTimeoutFlag
	lbne  	ERROR_TIMEOUT_EXIT
	; if here, nothing to do except wait for more incoming signals. reset network signal, and then sleep
	clr 	<networkDataReady
	; reset signal for network activity 
	lda 	<networkPath
	ldb 	#SS.SSig 
	ldx 	#network_signal
	os9 	I$SetStt 
	; sleep 
	ldx 	#0 
	os9 	F$Sleep 
	bra   	MAINLOOP

MAINLOOP_NEW_KEYSTROKES
	; if here, there was keyboard input. handle it
	lda  	<gfxWindowPath 
	ldb 	#SS.Ready 
 	os9 	I$GetStt
 	bcs  	MAINLOOP  	; something weird happened so ignore and go through mainloop again
 	clra 
 	tfr  	D,Y 
 	lda  	<gfxWindowPath
 	leax  	stringBuffer,U 
 	os9 	I$Read 
 	bcs  	MAINLOOP  	; something weird happened so ignore and go through mainloop again
 	clr  	<keyInputFlag ; reset keyInputFlag since all pending keystrokes have now been read in and cleared
 	tfr  	Y,D 
MAINLOOP_CHECK_NEXT_KEYSTROKE
 	lda 	,X+ 
 	cmpa 	#C$CR 
 	lbeq  	REFRESH_WEATHER_DATA_MANUALLY
 	decb 
 	bne  	MAINLOOP_CHECK_NEXT_KEYSTROKE
 	; if here, no ENTER key was pressed for a manual refresh of weather data. reset signal and go back to mainloop
 	lda  	<gfxWindowPath
	ldb 	#SS.SSig
	ldx 	#keyboard_signal
	os9 	I$SetStt
 	bra 	MAINLOOP

MAINLOOP_NEXT_READ
	lbsr 	DRIVEWIRE_GET_DATA
	bcs 	MAINLOOP  		; check and reset signals and then sleep until more data comes through

	lda 	<pendingConnect
	lbeq 	MAINLOOP_NEW_DATA 	; we are already connected so read in data from server reply

	; set our string matching search routine to stop looking within temp dw network buffer
	ldx  	<networkBufferEndPtr
	stx  	<searchEndPtr 

	leax 	networkBuffer,U 
	leay 	strKEYWORDok,PCR 
	lbsr 	STRING_SEARCH_BUFFER
	bcc 	MAINLOOP_NOW_CONNECTED
	leay 	strKEYWORDfail,PCR 
	lbsr 	STRING_SEARCH_BUFFER
	bcs 	MAINLOOP_NEXT_READ 		; ignore and look for further network data 
	; if here, connection to drivewire server failed. report reason 
	lbsr 	FIND_NEXT_SPACE_NULL_CR
	leax 	1,X 
	lbsr 	FIND_NEXT_SPACE_NULL_CR
	leax 	1,X 
	stx 	<tempPtr
	; disable timeout timer if exists 
	lda 	<nilPath 
	bmi 	MAINLOOP_SKIP_VRN_TIMER
	ldb 	#SS.FClr  
	ldx 	#0
	ldy 	#0
	os9 	I$SetStt 
MAINLOOP_SKIP_VRN_TIMER
	leay 	outputBuffer,U 
	leax 	strConnectFailed,PCR 
	lbsr 	STRING_COPY_RAW
	ldx 	<tempPtr 
	lbsr 	STRING_COPY_CR
	lda 	#')'
	sta 	,Y+
	ldd 	#cr_lf 
	std 	,Y++
	clr 	,Y 
	leax 	outputBuffer,U 
	lda 	#STDOUT 
	lbsr 	PRINT_NULL_STRING
	; close paths and exit 
	lbra 	CLOSE_EXIT

MAINLOOP_NOW_CONNECTED
	lda  	<refreshFlag
	beq  	MAINLOOP_NOW_CONNECTED_STDOUT
	; if here, we are in graphics mode and need to update status text
	leax  	strGfxRetrieving,PCR 
	lbsr  	PRINT_GFX_STATUS 	
	bra   	MAINLOOP_SETUP_WX_REQUEST

MAINLOOP_NOW_CONNECTED_STDOUT
	lda  	#STDOUT
	leax 	strConnectSuccess,PCR 
	lbsr 	PRINT_NULL_STRING
MAINLOOP_SETUP_WX_REQUEST
	clr 	<pendingConnect
	clr  	<copyContentFlag
	clr  	<contentLengthFlag
	; send the weather HTTP request to the server 
	lbsr 	SEND_WEATHER_REQUEST
	; check for any more data/response from the network 
	lbra 	MAINLOOP_NEXT_READ

MAINLOOP_NEW_DATA
	; first copy new data into our main buffer from temporary one
	leax  	networkBuffer,U 
	ldy  	<replyBufferEndPtr
	sty  	<replyBufferCurPtr 	; this now will become our new current ptr after copying
	ldb  	<dwReadBytes+1
MAINLOOP_NEW_DATA_COPY_NEXT
	lda  	,X+
	sta  	,Y+
	decb 
	bne  	MAINLOOP_NEW_DATA_COPY_NEXT
	sty  	<replyBufferEndPtr  	; save end position in reply buffer for future data to continue at
	sty  	<searchEndPtr

	lda  	<copyContentFlag
	beq  	MAINLOOP_CHECK_HEADER_STUFF
	; subtract new bytes we just copied in from total remaining of the main content and keep copying
	ldd  	<contentLength
	subd  	<dwReadBytes
	std   	<contentLength
	lbhi  	MAINLOOP_NEXT_READ  	; if we have not reached 0 (or less) bytes reamining, keep copying
	lbra  	PROCESS_WEATHER_DATA

MAINLOOP_CHECK_HEADER_STUFF
	lda  	<contentLengthFlag
	lbne  	MAINLOOP_NEW_DATA_FIND_BODY
	; before going any further, retrieve the HTTP server reply code to see if we have a valid
	; reply from the server, or some kind of error like "Bad Reqest" of "Not Found"
	leay  	strKEYWORDhttp1.1,PCR 
	ldx  	<replyBufferCurPtr
	lbsr  	STRING_SEARCH_BUFFER
	lbcs  	MAINLOOP_NEXT_READ
	; if here, we found the HTTP reply version. check the reply code and handle accordingly
	lbsr   FIND_NEXT_NONSPACE_CHAR
	ldd  	#"40"
	cmpd  	,X 
	bne  	MAINLOOP_CHECK_HEADER_VALID_REQUEST
	cmpa  	2,X 
	lbeq  	ERROR_LOCATION_NOT_FOUND
	lbra  	ERROR_UNKNOWN_SERVER_RESPONSE

MAINLOOP_CHECK_HEADER_VALID_REQUEST
	ldd  	#"20"
	cmpd  	,X 
	lbne  	ERROR_UNKNOWN_SERVER_RESPONSE
	cmpb  	2,X
	lbne  	ERROR_UNKNOWN_SERVER_RESPONSE
	; if here, we have a valid HTTP response code 200
	; now search for the content length information so we know how much weather data to read in
	leay  	strKEYWORDcontent,PCR 
	ldx  	<replyBufferCurPtr
	lbsr  	STRING_SEARCH_BUFFER
	lbcs  	MAINLOOP_NEXT_READ
	; if here, we found the content length number for HTTP reply
	inc  	<contentLengthFlag  	; set flag so next time through, we will search for content body
	; parse and copy content length value and convert to it's actual value
	ldb  	#5  		; limit value to 5 chars (4 for numbers + 1 CR)
MAINLOOP_CONTENT_LENGTH_FIND_CR
	lda  	,X+
	cmpa  	#C$CR 
	beq  	MAINLOOP_CONTENT_LENGTH_FOUND_CR
	decb 
	bne  	MAINLOOP_CONTENT_LENGTH_FIND_CR
MAINLOOP_CONTENT_LENGTH_FOUND_CR
	; now convert the ascii numbers into our actual content length value
	ldy  	#0
	clra
	leax  	-1,X  		; undo auto-increment
	ldb  	,-X  		; get singles place
	subb  	#'0' 		; convert to value 
	leay  	D,Y   		; add value to our total 
	ldb  	,-X 
	cmpb 	#C$SPAC 	; see if we reached beginning of content-length (and end of our calc)
	beq   	MAINLOOP_CONTENT_LENGTH_DONE
	subb  	#'0'
	lda  	#10  		; 10's
	mul 
	leay  	D,Y 
	ldb  	,-X 
	cmpb 	#C$SPAC 	; see if we reached beginning of content-length (and end of our calc)
	beq   	MAINLOOP_CONTENT_LENGTH_DONE
	subb  	#'0'
	lda  	#100  		; 100's
	mul 
	leay  	D,Y 
	ldb  	,-X 
	cmpb 	#C$SPAC 	; see if we reached beginning of content-length (and end of our calc)
	beq   	MAINLOOP_CONTENT_LENGTH_DONE
	subb  	#'0'
	; 1000's is a little trickier for multiplication
	lda  	#10
	mul 
	lda  	#100
	mul 
	leay  	D,Y 
	; never going to be more than 9999 bytes so skip finding higher multiples of 10
MAINLOOP_CONTENT_LENGTH_DONE
	sty  	<contentLength 
	sty  	<constContentLength
MAINLOOP_NEW_DATA_FIND_BODY
	; now find end of header (and start of actual body/content of HTTP request)
	leay  	strKEYWORDdoubleCRLF,PCR 
	ldx  	<replyBufferCurPtr
	lbsr  	STRING_SEARCH_BUFFER
	lbcs  	MAINLOOP_NEXT_READ	
	; if here, we found start of content body. now continously read the rest of the server reply from dw
	; until we reach the number of bytes in contentLength
	stx  	<contentBodyPtr
	; subtract the number of valid content bytes left in remainder of buffer from total content length count
	ldd  	<replyBufferEndPtr
	subd  	<contentBodyPtr
	std  	<tempWord
	ldd  	<contentLength
	subd  	<tempWord 
	std  	<contentLength
	inc  	<copyContentFlag 		; tell mainloop that from now on, just copy data until we run out
	lbra  	MAINLOOP_NEXT_READ

PROCESS_WEATHER_DATA
	; disable timeout timer since we got valid request and read all data
	lda 	<nilPath 
	bmi 	PROCESS_WEATHER_DATA_SKIP_VRN
	ldb 	#SS.FClr  
	ldx 	#0
	ldy 	#0
	os9 	I$SetStt 
PROCESS_WEATHER_DATA_SKIP_VRN
	lbsr  	PARSE_JSON_WEATHER_DATA
	; check if location wasn't found by searching for location name "Tong Not, Vietnam" because that is
	; what shows up for some reason when it cant find the location
	leax  	jsonAreaName,U 
	leay  	strKEYWORDtong,PCR 
	lbsr  	COMPARE_PARAM
	bcs  	PROCESS_WEATHER_DATA_VALID_AREA_FOUND
	lda  	jsonRegion,U 
	lbeq  	ERROR_LOCATION_NOT_FOUND
PROCESS_WEATHER_DATA_VALID_AREA_FOUND
	lda 	<refreshFlag
	bne  	PROCESS_WEATHER_DATA_SKIP_STDOUT
	; tell user we successfully finished retreiving data and found valid result
	lda  	#STDOUT 
	leax  	strDone,PCR 
	lbsr  	PRINT_NULL_STRING
PROCESS_WEATHER_DATA_SKIP_STDOUT
DEBUG_WTTR_DOWN
	leax  	jsonPressure,U 
	lbsr   CONVERT_HPA_TO_INHG 

	lda  	<outputMode
	lbeq  	OUTPUT_GRAPHICS_MODE
	; ok user wants text-only output. build our formatted output string from the data 
	leay  	outputBuffer,U 
	leax  	strCurrentWeather,PCR 
	lbsr  	STRING_COPY_RAW
	leax  	jsonAreaName,U 
	lbsr  	STRING_COPY_RAW
	ldd  	#", "
	std  	,Y++
	leax  	jsonRegion,U 
	lbsr  	STRING_COPY_RAW
	ldd  	#": "
	std  	,Y++
	leax  	jsonWeatherDesc,U 
	lbsr  	STRING_COPY_RAW
	leax  	strTemperature,PCR 
	lbsr  	STRING_COPY_RAW
	lda  	<metricOutputFlag
	bne   	TEXT_SHOW_METRIC_TEMP
	leax  	jsonTempF,U 
	ldb  	#'F'
	bra  	TEXT_TEMP_STORE

TEXT_SHOW_METRIC_TEMP
	leax  	jsonTempC,U 
	ldb  	#'C'
TEXT_TEMP_STORE
	lbsr  	STRING_COPY_RAW
	lda  	<charDegreesSymbol
	std  	,Y++
	leax  	strFeelsLike,PCR 
	lbsr  	STRING_COPY_RAW
	lda  	<metricOutputFlag
	bne  	TEXT_SHOW_METRIC_FEELS_LIKE
	leax  	jsonFeelsLikeF,U 
	ldb  	#'F'
	bra   	TEXT_FEELS_LIKE_STORE

TEXT_SHOW_METRIC_FEELS_LIKE
	leax  	jsonFeelsLikeC,U 
	ldb  	#'C'
TEXT_FEELS_LIKE_STORE
	lbsr  	STRING_COPY_RAW
	lda  	<charDegreesSymbol
	std  	,Y++
	leax   strHumidity,PCR 
	lbsr  	STRING_COPY_RAW
	leax  	jsonHumidity,U 
	lbsr 	STRING_COPY_RAW
	lda  	#'%'
	sta  	,Y+
	leax   strPressure,PCR 
	lbsr  	STRING_COPY_RAW
	;leax   jsonPressure,U 
	lda  	<metricOutputFlag
	bne  	TEXT_SHOW_METRIC_PRESSURE
	leax  	pressureInches,U 
	lbsr  	STRING_COPY_RAW
	leax   strPressureInHg,PCR 
	bra  	TEXT_PRESSURE_STORE

TEXT_SHOW_METRIC_PRESSURE
	leax  	jsonPressure,U 
	lbsr  	STRING_COPY_RAW
	leax  	strPressurehPa,PCR 
TEXT_PRESSURE_STORE
	lbsr  	STRING_COPY_RAW
	leax  	strWind,PCR 
	lbsr  	STRING_COPY_RAW
	leax  	jsonWindDir,U 
	lbsr  	STRING_COPY_RAW
	ldd  	#" a"
	std  	,Y++
	ldd  	#"t "
	std  	,Y++
	lda  	<metricOutputFlag
	bne   	TEXT_SHOW_METRIC_WIND_SPEED
	leax  	jsonWindSpeedMPH,U 
	lbsr  	STRING_COPY_RAW
	leax  	strWindMPH,PCR 
	bra  	TEXT_WIND_SPEED_STORE

TEXT_SHOW_METRIC_WIND_SPEED
	leax   jsonWindSpeedKPH,U 
	lbsr  	STRING_COPY_RAW
	leax  	strWindKPH,PCR 
TEXT_WIND_SPEED_STORE
	lbsr  	STRING_COPY_RAW
	leax  	strPrecipitation,PCR 
	lbsr  	STRING_COPY_RAW
	lda  	<metricOutputFlag
	bne  	TEXT_SHOW_METRIC_RAIN
	leax  	jsonPrecipInches,U 
	lbsr  	STRING_COPY_RAW
	lda  	#C$SPAC 
	sta  	,Y+
	ldd  	#"in"
	std  	,Y++
	bra   	TEXT_RAIN_DONE

TEXT_SHOW_METRIC_RAIN
	leax  	jsonPrecipMM,U 
	lbsr  	STRING_COPY_RAW
	lda  	#C$SPAC 
	sta  	,Y+
	ldd  	#"mm"
	std  	,Y++
TEXT_RAIN_DONE
	leax  	strDateTime,PCR 
	lbsr  	STRING_COPY_RAW
	leax  	jsonLocalTime,U 
	lbsr  	STRING_COPY_RAW
	ldd  	#cr_lf
	std 	,Y++
	clr  	,Y 

	lda  	#STDOUT 
	leax  	outputBuffer,U 
	lbsr   PRINT_NULL_STRING

	lbra 	CLOSE_EXIT

OUTPUT_GRAPHICS_MODE
	; check if we are displaying gfx weather for first time or if this is a refresh of existing data
	lda  	<refreshFlag
	lbne  	DISPLAY_REFRESHED_GRAPHICS

	; tell the user we are about to load the graphics assets from disk
	lda  	#STDOUT
	leax  	strMsgLoadingGfx,PCR 
	lbsr  	PRINT_NULL_STRING

	; do some initial setup for gfx display the first time through
 	; get process ID that was assigned to us
 	os9  	F$ID 
 	sta 	groupID,U 

 	; setup a path to create new graphics window 
 	lda 	#UPDAT. 
 	clrb 
 	leax 	winPathName,PCR 
 	os9  	I$Open 
 	sta 	gfxWindowPath,U 
 	; now setup the window params etc
       leax 	dwSetWindow,PCR 
       ldy 	#dwSetWindowSz
      	os9 	I$Write 

	lbsr  	SET_KEYBOARD_RAW 	; setup raw IO mode for keyboard input for after weather is displayed
   	lbsr 	LOAD_ALL_GFX_DIGITS	; load all the graphics digits into all their GET/PUT buffers

     	; setup the colors for text
      	leay 	outputBuffer,U 
      	ldd 	#$1B32
      	std 	,Y++
      	lda 	#7
      	sta 	,Y+
      	ldd 	#$1B33 
      	std 	,Y++
      	lda 	#16 					; same as a 0 without interferring with string nulls
      	sta 	,Y+
      	leax  	outputBuffer,U 
      	lda 	gfxWindowPath,U
      	lbsr  	PRINT_NULL_STRING

      ; ------ display title -------
      lda 	gfxWindowPath,U 
      leax  	selectFontTitle,PCR 
      ldy  	#4
      os9  	I$Write 
      
      lda 	#10
      lbsr 	CHANGE_TEXT_COLOR
      lda 	#20 				; center text based on middle position of 40 column width screen 
      clrb 
      leax 	strGfxCoCoWX,PCR 
      lbsr 	PRINT_NULL_STRING_CENTER_RELATIVE
      leax  	selectFontAuthor,PCR 
      ldy  	#4
      lda  	<gfxWindowPath
      os9 	I$Write 
      
      lda  	#11 
      lbsr   	CHANGE_TEXT_COLOR
      lda  	#20
      ldb  	#2
      leax  	strGfxAuthor,PCR 
      lbsr  	PRINT_NULL_STRING_CENTER_RELATIVE

DISPLAY_REFRESHED_GRAPHICS
      	; load appropriate weather conditions icon based on code from json data
      	leax  	jsonWeatherCode,U 
      	lbsr  	LOAD_WX_CONDITIONS_ICON
      	lbcs  	ERROR_GRAPHICS_MISSING
      	bmi  	SKIP_ICON_SINCE_NOT_FOUND

      	; load the wind direction compass graphics
      	leax  	jsonWindDir,U 
 	lbsr  	LOAD_WIND_ICON
 	lbcs  	ERROR_GRAPHICS_MISSING

 	lda  	<refreshFlag
 	beq  	DISPLAY_REFRESHED_GRAPHICS_PRINT_STDOUT
 	; if here, we are processing a wx data refresh. erase previous weather graphics/info before
 	; displaying updated ones
	lda  	<gfxWindowPath
	leax  	screenUpdateSeq,PCR 		; clears most of the screen (except for program name/author/etc)
	ldy  	#screenUpdateSeqSz
	os9  	I$Write
	bra  	DISPLAY_REFRESHED_GRAPHICS_SKIP_STDOUT

DISPLAY_REFRESHED_GRAPHICS_PRINT_STDOUT
 	; tell user graphics are done loading from disk
 	lda  	#STDOUT
 	leax  	strDone,PCR 
	lbsr  	PRINT_NULL_STRING
DISPLAY_REFRESHED_GRAPHICS_SKIP_STDOUT
      	; PUT graphics objects onto screen and then select whole screen making it visible
      	; first PUT the weather condition icon
      	leax 	outputBuffer,U 
      	ldd 	#$1B2D 		; PutBlk sequence 
      	std 	,X++
      	lda 	groupID,U 
      	ldb 	#1
      	std 	,X++
      	ldd  	#30
      	std 	,X++ 
      	ldd  	#69   			; Y coords to put weather icon graphic
      	std 	,X++

    ;  	lda  	<refreshFlag
     ; 	bne  	DWSELECT_SKIP
      	; TEMPORARY
      ;	ldd 	#$1B21 		; DWSelect sequence
      ;	std 	,X++ 
;DWSELECT_SKIP
      	lda  	<gfxWindowPath
      	leax  	outputBuffer,U 
      	ldy  	#8
      	os9  	I$Write 
SKIP_ICON_SINCE_NOT_FOUND
      	; ---------- show location -------------
	lda 	gfxWindowPath,U 
	leax  	selectFontInfo,PCR 
	ldy  	#4
	os9  	I$Write 

      	leay  	stringBuffer,U 
      	leax  	jsonAreaName,U 
      	lbsr  	STRING_COPY_RAW
      	ldd  	#", "
      	std  	,Y++
      	leax   jsonRegion,U 
      	lbsr  	STRING_COPY_RAW
      	lda 	#7
      	lbsr 	CHANGE_TEXT_COLOR
      	lda 	#27 		
      	ldb 	#5
      	leax  	stringBuffer,U 
      	lbsr  	PRINT_NULL_STRING_CENTER_RELATIVE

      ; ---------- show text conditions info ----------
      	lda   	#10
    	ldb  	#19
  	leax  	jsonWeatherDesc,U 
      	lbsr  	PRINT_NULL_STRING_CENTER_RELATIVE
      	
      	leay  	stringBuffer,U 
      	lda  	<metricOutputFlag
      	bne  	GFX_SHOW_METRIC_TEMP
      	leax  	jsonTempF,U 
      	ldb  	#'F'
      	bra  	GFX_TEMP_STORE

GFX_SHOW_METRIC_TEMP
	leax  	jsonTempC,U 
	ldb  	#'C'
GFX_TEMP_STORE
	lbsr  	STRING_COPY_RAW
      	lda  	<charDegreesSymbol
      	std  	,Y++
      	clr  	,Y   	
      	leax  	stringBuffer,U 
      	ldd  	#120
      	ldy  	#72
      	lbsr  	PRINT_LARGE_DIGITS_STRING

   	; -------- show feels like temp -------
   	leay  	outputBuffer,U 
	lda 	#$02 					; reposition text cursor code 
	sta  	,Y+
	lda  	#$20+20
	ldb   	#$20+15
	std  	,Y++
   	leax  	strGfxFeelsLike,PCR 
   	lbsr  	STRING_COPY_RAW
   	leax  	infoColorSequence,PCR 
   	lbsr  	STRING_COPY_RAW
   	lda  	<metricOutputFlag
   	bne  	GFX_SHOW_METRIC_FEELS_LIKE
   	leax  	jsonFeelsLikeF,U 
   	ldb  	#'F'
   	bra   	GFX_FEELS_LIKE_STORE

GFX_SHOW_METRIC_FEELS_LIKE
	leax  	jsonFeelsLikeC,U 
	ldb  	#'C'
GFX_FEELS_LIKE_STORE
   	lbsr  	STRING_COPY_RAW
   	lda  	#$BE
   	std  	,Y++
   	clr  	,Y
	leax   outputBuffer,U  
	lda   	gfxWindowPath,U 
	lbsr   PRINT_NULL_STRING

	; -------- show humidity ---------
	leay   outputBuffer,U 
	lda 	#$02 					; reposition text cursor code 
	sta  	,Y+
	lda  	#$20+20
	ldb   	#$20+17
	std  	,Y++
	leax  	labelColorSequence,PCR 
	lbsr  	STRING_COPY_RAW
	leax   strGfxHumidity,PCR 
	lbsr  	STRING_COPY_RAW
   	leax  	infoColorSequence,PCR 
   	lbsr  	STRING_COPY_RAW
	leax   jsonHumidity,U 
	lbsr   STRING_COPY_RAW
	lda  	#'%'
	clrb 
	std  	,Y++
	leax   outputBuffer,U  
	lda   	gfxWindowPath,U 
	lbsr   PRINT_NULL_STRING

      	; ------- show pressure --------
      	leay  	outputBuffer,U 
      	lda   	#$02
      	sta  	,Y+ 
      	lda  	#$20+20
      	ldb  	#$20+19 
      	std 	,Y++
	leax  	labelColorSequence,PCR 
	lbsr  	STRING_COPY_RAW
      	leax   strGfxPressure,PCR 
      	lbsr   STRING_COPY_RAW
   	leax  	infoColorSequence,PCR 
   	lbsr  	STRING_COPY_RAW
   	lda  	<metricOutputFlag
   	bne  	GFX_SHOW_METRIC_PRESSURE
      	leax   pressureInches,U 
      	lbsr   STRING_COPY_RAW
      	leax   strPressureInHg,PCR 
      	bra  	GFX_PRESSURE_STORE

GFX_SHOW_METRIC_PRESSURE
	leax  	jsonPressure,U 
	lbsr  	STRING_COPY_RAW
	leax  	strPressurehPa,PCR 
GFX_PRESSURE_STORE
      	lbsr  	STRING_COPY_RAW
      	leax  	outputBuffer,U 
      	lda  	gfxWindowPath,U 
      	lbsr   PRINT_NULL_STRING

	; ------- show wind --------
	leax  	outputBuffer,U 
	ldd 	#$1B2D 		; PutBlk sequence 
      	std 	,X
      	lda 	groupID,U 
      	ldb 	#20  			; 20 for wind dir GET/PUT buffer
      	std 	2,X
      	ldd  	#243
      	std  	4,X
      	ldd  	#89   		; Y coords to put wind direction icon graphic
      	std  	6,X
      	; PUT graphic on the screen
      	ldy  	#8
      	lda  	<gfxWindowPath
      	os9  	I$Write 
      	; now do the text parts starting with the "Wind" label
      	leay  	outputBuffer,U 
      	lda   	#$02
      	sta  	,Y+ 
      	lda  	#$20+41
      	ldb  	#$20+9
      	std  	,Y++
 	leax  	labelColorSequence,PCR 
	lbsr  	STRING_COPY_RAW     	
      	leax  	strGfxWind,PCR  
      	lbsr  	STRING_COPY_RAW
     	lda  	#$02
     	sta  	,Y+
      	lda  	#$20+40
      	ldb  	#$20+16
      	std 	,Y++
      	lda  	<metricOutputFlag
      	bne   	GFX_SHOW_METRIC_WIND_SPEED
      	leax  	jsonWindSpeedMPH,U 
      	lbsr  	STRING_COPY_RAW
      	leax  	strWindMPH,PCR 
      	bra  	GFX_WIND_SPEED_STORE

GFX_SHOW_METRIC_WIND_SPEED
	leax  	jsonWindSpeedKPH,U 
	lbsr  	STRING_COPY_RAW
	leax  	strWindKPH,PCR 
GFX_WIND_SPEED_STORE
      	lbsr  	STRING_COPY_RAW
      	; now write the whole thing to screen
      	leax  	outputBuffer,U 
      	lda  	<gfxWindowPath
      	clrb 
      	lbsr  	PRINT_NULL_STRING  
      	; ------ show rainfall --------------------
      	leay  	outputBuffer,U 
      	lda   	#$02
      	sta  	,Y+ 
      	lda  	#$20+20
      	ldb  	#$20+21 
      	std 	,Y++
	leax  	labelColorSequence,PCR 
	lbsr  	STRING_COPY_RAW
      	leax   strGfxRainfall,PCR 
      	lbsr   STRING_COPY_RAW
   	leax  	infoColorSequence,PCR 
   	lbsr  	STRING_COPY_RAW
   	lda  	<metricOutputFlag
   	bne  	GFX_SHOW_METRIC_RAINFALL
      	leax   jsonPrecipInches,U  
      	lbsr   STRING_COPY_RAW
      	lda  	#C$SPAC 
      	sta  	,Y+ 
      	ldd  	#"in"
      	bra  	GFX_RAINFALL_STORE

GFX_SHOW_METRIC_RAINFALL
	leax  	jsonPrecipMM,U 
	lbsr  	STRING_COPY_RAW
	lda  	#C$SPAC 
	sta  	,Y+
	ldd  	#"mm"
GFX_RAINFALL_STORE
	std  	,Y++
	clr  	,Y 
      	leax  	outputBuffer,U 
      	lda  	gfxWindowPath,U 
      	lbsr   PRINT_NULL_STRING 	

      	lda  	<refreshFlag
      	bne 	GFX_SKIP_DWSELECT
      	; issue DWSelect to show the main window now
      	lda  	<gfxWindowPath
      	leax  	dwSelectSequence,PCR 
      	ldy  	#2 
      	os9  	I$Write 
GFX_SKIP_DWSELECT
      	; ------ show obervation date/time --------
      	leay  	stringBuffer,U 
      	leax  	labelColorSequence,PCR 
	lbsr  	STRING_COPY_RAW
      	leax  	strGfxObsTime,PCR 
      	lbsr  	STRING_COPY_RAW
      	leax  	jsonLocalTime,U 
      	lbsr  	STRING_COPY_RAW
      	leax  	stringBuffer,U  
	lbsr  	PRINT_GFX_STATUS

	; and we are done! now close the current open DW path since we'll lose it anyways when the HTTP server
	; closes connection
	lda  	<networkPath
	os9  	I$Close 
	; mark the path flag as unopened
	lda  	#$FF 
	sta  	<networkPath

	clra 
      	sta 	<networkDataReady
      	sta 	<pendingConnect
      	sta 	<networkTimeoutFlag

      	; enable auto-refresh timer
	lda 	<nilPath
	ldb 	#SS.FSet  	; code $C7
	ldx 	#36000 	; 10 minutes
	ldy 	#0
	ldu 	#wx_refresh_signal
	os9 	I$SetStt 
	ldu 	<uRegImage

	; setup the signal for keyboard input to check for ENTER press for manual refresh of wx data
	clr  	<keyInputFlag
	lda 	<gfxWindowPath
	ldb 	#SS.SSig
	ldx 	#keyboard_signal
	os9 	I$SetStt

	lbra  	MAINLOOP

REFRESH_WEATHER_DATA_MANUALLY
	; we first have to disable the regular refresh timer since user requested an immediate manual update
	lda  	<nilPath
	ldb  	#SS.FClr
	ldx 	#0
	ldy 	#0
	os9 	I$SetStt 
REFRESH_WEATHER_DATA
	; inform user we are about to request updated weather for the place they initially requested 
	clr  	<wxRefreshFlag

	leax  	strGfxConnecting,PCR 
	lbsr  	PRINT_GFX_STATUS

	; let the program know that everything was already set it up once and just updates from now on
	lda  	#1
	sta  	<refreshFlag 	
	
	lbra  	SETUP_REFRESH_WEATHER_REQUEST

DISPLAY_INFO_USAGE
	lda 	#STDOUT 
	leax 	strUsage,PCR 
	ldy 	#strUsageSz
	os9 	I$Write 
	bra 	CLOSE_EXIT

ERROR_UNKNOWN_SERVER_RESPONSE
	; X should still be pointed to server error code in the HTTP reply header
	stx  	<tempPtr
	leay  	outputBuffer,U 
	leax  	strErrorServerReply,PCR 
	lbsr  	STRING_COPY_RAW
	ldx  	<tempPtr
	lbsr  	STRING_COPY_CR
	lda  	#')'
	ldb  	#C$CR 
	std 	,Y
	ldd  	#$0A00 
	std  	2,Y
	leax  	outputBuffer,U 
	bra  	CLOSE_EXIT_PRINT_STDOUT

ERROR_INVALID_PARAMS
	leax 	strErrorInvalidParam,PCR
	bra 	CLOSE_EXIT_PRINT_STDOUT

ERROR_UNKNOWN_FLAG
	leax 	strErrorInvalidFlag,PCR 
	bra 	CLOSE_EXIT_PRINT_STDOUT

ERROR_TIMEOUT_EXIT
	lda  	<refreshFlag
	beq  	ERROR_TIMEOUT_EXIT_STDOUT
	; if here, we are in graphics output mode so tell them request timed out
	leax  	strGfxTimeout,PCR 
	lbsr  	PRINT_GFX_STATUS
	bra  	CLOSE_EXIT

ERROR_TIMEOUT_EXIT_STDOUT
	leax 	strErrorTimeout,PCR 
	bra 	CLOSE_EXIT_PRINT_STDOUT

ERROR_NO_DRIVEWIRE
	leax 	strErrorNoDrivewire,PCR 
	bra 	CLOSE_EXIT_PRINT_STDOUT

ERROR_LOCATION_NOT_FOUND
	leay  	outputBuffer,U 
	leax  	strErrorLocation,PCR 
	lbsr  	STRING_COPY_RAW
	ldx  	<shellParamPtr
	lbsr  	STRING_COPY_CR
	lda  	#')'
	ldb  	#C$CR 
	std 	,Y
	ldd  	#$0A00 
	std  	2,Y
	leax  	outputBuffer,U 
	bra  	CLOSE_EXIT_PRINT_STDOUT

ERROR_GRAPHICS_MISSING
	leax  	strErrorGraphics,PCR 
	bra  	CLOSE_EXIT_PRINT_STDOUT

USER_ABORT_EXIT
	lda  	<gfxWindowPath
	bmi  	USER_ABORT_EXIT_SKIP_GFX_CLOSE
	os9  	I$Close 
USER_ABORT_EXIT_SKIP_GFX_CLOSE
	leax 	strUserAborted,PCR
CLOSE_EXIT_PRINT_STDOUT
	lda 	#STDOUT 
	lbsr 	PRINT_NULL_STRING
CLOSE_EXIT
	lda  	<gfxWindowPath
	bmi  	CLOSE_EXIT_SKIP_GFX
	os9  	I$Close 
CLOSE_EXIT_SKIP_GFX
	lda 	<nilPath
	bmi 	CLOSE_EXIT_SKIP_VRN
	os9 	I$Close 
CLOSE_EXIT_SKIP_VRN
	lda 	<networkPath
	bmi 	PROGRAM_EXIT 		; if no path was ever opened, skip the close call 
	os9 	I$Close 
PROGRAM_EXIT
	clrb 
      	os9 	F$Exit 

; --------------------------------------------------------------------
; signal handler 
; --------------------------------------------------------------------
SIGNAL_HANDLER
	cmpb 	#network_signal 
	beq 	SIGNAL_HANDLER_NETWORK
	cmpb 	#connect_timeout_signal
	beq 	SIGNAL_HANDLER_NETWORK_TIMEOUT
	cmpb  	#keyboard_signal
	beq   	SIGNAL_HANDLER_KEYBOARD
	cmpb  	#wx_refresh_signal
	beq  	SIGNAL_HANDLER_WX_REFRESH
	cmpb 	#S$Intrpt
	beq 	SIGNAL_HANDLER_ABORT
	cmpb 	#S$Abort
	beq 	SIGNAL_HANDLER_ABORT
	rti 

SIGNAL_HANDLER_NETWORK
	inc 	<networkDataReady
	rti 

SIGNAL_HANDLER_NETWORK_TIMEOUT
	inc 	<networkTimeoutFlag
	rti

SIGNAL_HANDLER_KEYBOARD
	inc  	<keyInputFlag
	rti 

SIGNAL_HANDLER_WX_REFRESH
	inc  	<wxRefreshFlag
	rti 

SIGNAL_HANDLER_ABORT
	inc 	<abortFlag
	rti 

; --------------------------------------------------------------------
; setup drivewire server network paths 
; --------------------------------------------------------------------
DRIVEWIRE_SETUP
	pshs 	Y,X,D 

	lda 	#UPDAT. 
	leax 	networkPathName,PCR 
	os9 	I$Open 
	bcs 	DRIVEWIRE_SETUP_EXIT
	sta 	<networkPath 

	ldb 	#SS.Opt  
	leax 	pdBuffer,U 
	os9 	I$GetStt
	bcs 	DRIVEWIRE_SETUP_EXIT

	; switch to RAW mode instead now 
       leax 	PD.UPC-PD.OPT,X
	ldb 	#PD.QUT-PD.UPC 
DRIVEWIRE_SETUP_RAW_LOOP        
	clr 	,X+
	decb
	bpl 	DRIVEWIRE_SETUP_RAW_LOOP

	lda 	<networkPath
	ldb 	#SS.Opt  
	leax 	pdBuffer,U 
	os9 	I$SetStt 
	bcs 	DRIVEWIRE_SETUP_EXIT

	; setup the initial network signal 
	lda 	<networkPath
	ldb 	#SS.SSig 
	ldx 	#network_signal
	os9 	I$SetStt 

DRIVEWIRE_SETUP_EXIT
	; carry will already be set if error or clear if not 
	puls 	D,X,Y,PC 

; -------------------------------------------------------------------
; check if drivewire server has new data for us and read it if we do 
; -------------------------------------------------------------------
DRIVEWIRE_GET_DATA
	pshs 	X

	; check if we have data to read before trying to do it 
	lda 	<networkPath	
	ldb 	#SS.Ready
	os9 	I$GetStt
	bcs 	DRIVEWIRE_GET_DATA_ERROR
	clra 
	tfr 	D,Y 
	lda 	<networkPath
	leax 	networkBuffer,U 
	os9 	I$Read 
	bcs 	DRIVEWIRE_GET_DATA_ERROR
	tfr 	Y,D 
	leax  	D,X 
	stx  	<networkBufferEndPtr
	std   	<dwReadBytes
DRIVEWIRE_GET_DATA_ERROR
	puls 	X,PC 

; ----------------------------------------------------------------------
SET_KEYBOARD_RAW
	pshs  	X,D 

	lda 	<gfxWindowPath
	ldb 	#SS.Opt  
	leax 	pdBuffer,U 
	os9 	I$GetStt
	bcs 	SET_KEYBOARD_RAW_EXIT

	; switch to RAW mode  
       leax 	PD.UPC-PD.OPT,X
	ldb 	#PD.INT-PD.UPC 
SET_KEYBOARD_RAW_LOOP        
	clr 	,X+
	decb
	bpl 	SET_KEYBOARD_RAW_LOOP

	lda 	<gfxWindowPath
	ldb 	#SS.Opt  
	leax 	pdBuffer,U 
	os9 	I$SetStt 
SET_KEYBOARD_RAW_EXIT
	puls  	D,X,PC 

; ----------------------------------------------------------------------
PRINT_BYTE_HEX
      pshs  U,Y,X,D

      ;ldu   <uRegImage

      leax  asciiHexList,PCR
      leay strHexWord,U 
      lda   #'$'
      sta   ,Y  
   
      lda   <u8Value
      lsra 
      lsra
      lsra
      lsra
      lda   A,X
      sta   1,Y              ; store first digit

      lda   <u8Value 
      anda  #$0F
      lda   A,X 
      clrb
      std   2,Y               ; store second digit

      leax  strHexWord,U
      lbsr  PRINT_NULL_STRING

      puls  D,X,Y,U,PC 

; --------------------------------------------------------------------
; Entry: X = pointer to string to print as status update
; --------------------------------------------------------------------
PRINT_GFX_STATUS
	pshs  	Y,X,D 

	; move cursor to status area, clear that line, copy in text from entry pointer, and display it
	leay  	outputBuffer,U 
	lda  	#$02
	sta  	,Y+
	lda  	#$20+7
	ldb  	#$20+24
	std  	,Y++
	lda  	#$03 
	sta  	,Y+ 
	lda  	#$02
	sta  	,Y+
	ldd  	#$2744
	std  	,Y++
	; X should still contain pointer to string to display
	lbsr  	STRING_COPY_RAW
	lda  	<gfxWindowPath
	leax  	outputBuffer,U 
	lbsr  	PRINT_NULL_STRING

	puls  	D,X,Y,PC 

; --------------------------------------------------------------------
SEND_WEATHER_REQUEST
	pshs 	Y,X,D 

	leay 	outputBuffer,U 
	leax 	strGetPrefix,PCR 
	lbsr 	STRING_COPY_RAW
	ldx 	<shellParamPtr
	lbsr 	LOCATION_COPY
	leax 	strWeatherFormatTxt,PCR 
	lbsr 	STRING_COPY_RAW
	leax 	strGetSuffix,PCR
	lbsr 	STRING_COPY_RAW
	leax 	strHostInfo,PCR 
	lbsr 	STRING_COPY_RAW
	leax 	strUserAgent,PCR 
	lbsr 	STRING_COPY_RAW

	leax 	outputBuffer,U 
	lbsr 	FIND_LEN_UNTIL_EOF
	lda 	<networkPath
	os9 	I$Write 

	puls 	D,X,Y,PC 

; ----------------------------------------------------------------------
PARSE_JSON_WEATHER_DATA
	pshs  	U,Y,X,D 

	; make sure U contains usual os9 pointer to data area of vars
	leay  	jsonKeywordCurCond,PCR 
	ldx   	<contentBodyPtr
	lbsr  	SEARCH_JSON_KEYWORD
	lbcs   PARSE_JSON_WEATHER_DATA_ERROR
	stx  	<jsonCurCondPtr 

	lda  	#json_keyword_vars_sz
	sta  	<jsonTableCounter
	leau 	jsonKeywordVarsTable,PCR 
PARSE_JSON_WEATHER_DATA_NEXT_ENTRY
	ldx  	<jsonCurCondPtr
	ldd   	,U++
	leay  	0,PCR 
	leay  	D,Y 
	lbsr  	SEARCH_JSON_KEYWORD
	bcc  	PARSE_JSON_WEATHER_DATA_FOUND_PARAM
	; since we couldnt find that variable, load and copy blank/empty entry
	leax  	strBlank,PCR 
PARSE_JSON_WEATHER_DATA_FOUND_PARAM
	; now get pointer to destination variable to copy to for corresponding table entry
	ldy  	6,S  		; load pointer to data area for os9 vars on stack in U 
	ldd 	,U++
	leay  	D,Y 
	lbsr  	COPY_JSON_VARIABLE
	dec  	<jsonTableCounter
	bne  	PARSE_JSON_WEATHER_DATA_NEXT_ENTRY
	; now copy the more complicated parameters with multiple layers of elements
	ldu  	6,S   				; restore normal os9 data area ptr from stack 
	leay  	strJSONweatherDesc,PCR 
	ldx 	<jsonCurCondPtr
	lbsr  	SEARCH_JSON_KEYWORD
	bcs  	PARSE_JSON_WEATHER_DATA_ERROR
	leay  	strJSONvalue,PCR 
	lbsr  	SEARCH_JSON_KEYWORD
	bcs  	PARSE_JSON_WEATHER_DATA_ERROR
	leay   jsonWeatherDesc,U 
	lbsr  	COPY_JSON_VARIABLE
	; grab the area name text which has proper capitalization etc
	leay  	strJSONnearestArea,PCR 
	ldx  	<jsonCurCondPtr
	lbsr  	SEARCH_JSON_KEYWORD
	bcs  	PARSE_JSON_WEATHER_DATA_ERROR
	stx  	<tempPtr  		; save ptr to start of "Nearest Area" section
	leay  	strJSONareaName,PCR 
	lbsr  	SEARCH_JSON_KEYWORD
	bcs  	PARSE_JSON_WEATHER_DATA_ERROR
	leay  	strJSONvalue,PCR 
	lbsr  	SEARCH_JSON_KEYWORD
	bcs   	PARSE_JSON_WEATHER_DATA_ERROR
	leay  	jsonAreaName,U 
	lbsr  	COPY_JSON_VARIABLE
	; now the state or region 
	leay  	strJSONregion,PCR 
	ldx  	<tempPtr
	lbsr  	SEARCH_JSON_KEYWORD
	bcs  	PARSE_JSON_WEATHER_DATA_ERROR
	leay  	strJSONvalue,PCR 
	lbsr  	SEARCH_JSON_KEYWORD
	bcs   	PARSE_JSON_WEATHER_DATA_ERROR
	leay  	jsonRegion,U 
	lbsr  	COPY_JSON_VARIABLE
PARSE_JSON_WEATHER_DATA_DONE
	puls  	D,X,Y,U,PC 

PARSE_JSON_WEATHER_DATA_ERROR
	puls   D,X,Y,U,PC

; --------------------------------------------------------------------------
SEARCH_JSON_KEYWORD
	pshs  	Y,X,D 

SEARCH_JSON_KEYWORD_OPEN_NEXT
	; find an open-quote
	lbsr  	FIND_NEXT_QUOTE_CHAR
	bcs  	SEARCH_JSON_KEYWORD_FAILED
SEARCH_JSON_KEYWORD_FOUND_OPEN_QUOTE
	ldy  	4,S  	; reset ptr to keyword we are trying to match
	clrb 
SEARCH_JSON_KEYWORD_CHECK_NEXT
	lda  	,Y+
	beq   	SEARCH_JSON_KEYWORD_CHECK_TERMINATOR
	cmpa  	,X+
	bne  	SEARCH_JSON_KEYWORD_JUMP_NEXT
	decb 
	bne 	SEARCH_JSON_KEYWORD_CHECK_NEXT
SEARCH_JSON_KEYWORD_FAILED
	orcc  	#1
	puls  	D,X,Y,PC 

SEARCH_JSON_KEYWORD_JUMP_NEXT
	; something didnt match so first find the close-quote of current mismatched word so we can
	; start finding open-quote of next keyword
	leax 	-1,X  				; undo auto increment
	lbsr  	FIND_NEXT_QUOTE_CHAR
	bcc  	SEARCH_JSON_KEYWORD_OPEN_NEXT  ; found close-quote. go search for new open quote now for next keyword
	bra   	SEARCH_JSON_KEYWORD_FAILED

SEARCH_JSON_KEYWORD_CHECK_TERMINATOR
	lda  	,X+
	cmpa  	#$22  	; check for close-quote to confirm the keyword matches exactly with no extra chars left
	bne  	SEARCH_JSON_KEYWORD_JUMP_NEXT 	; nope, jump to search for new json keyword to try
	lda  	,X+
	cmpa  	#':'
	bne  	SEARCH_JSON_KEYWORD_FAILED  	; syntax doesnt match so fail
	lbsr   FIND_NEXT_NONSPACE_CHAR
	; if here, we successfully matched out keyword. save new ptr to stack and return
	stx  	2,S  
	andcc 	#$FE 
	puls  	D,X,Y,PC 

; ------------------------------------------------------------------------
; Entry: X = pointer to start of json parameter value
; 	  Y = destination to copy to
; Exit: on success, Y = pointer to null terminator. 
;  -----------------------------------------------------------------------
COPY_JSON_VARIABLE
	pshs  	X,D  

	lbsr  	FIND_NEXT_QUOTE_CHAR
	; found start of the element. copy until terminating quote mark
	ldb  	#32   	; variable should never be more than 32 chars (protect against overflow) 
COPY_JSON_VARIABLE_COPY_NEXT
	lda  	,X+
	cmpa  	#$22
	beq   	COPY_JSON_VARIABLE_DONE
	sta  	,Y+ 
	decb 
	bne  	COPY_JSON_VARIABLE_COPY_NEXT
	; if here, overflow happened
COPY_JSON_VARIABLE_ERROR
	orcc 	#1
	puls  	D,X,PC 

COPY_JSON_VARIABLE_DONE
	clr  	,Y 
	andcc  #$FE 
	puls  	D,X,PC 

; ------------------------------------------------------------------------------
; Convert pressure in hPa to american units inHg. HUGE THANKS to David Philipsen
; for writing the actual math parts!
; Entry: X = pointer to ascii string with hPa number to convert
; Exit: v24h, v24m, v24l will be populated with 24 bit integer representing inHg
; 	 the first 2 numbers are the real integers but rest are decimals
; ------------------------------------------------------------------------------
CONVERT_HPA_TO_INHG
	pshs  	Y,X,D  

	ldd 	#0
	std  	<hpaValue
	; find end of number in hpa and convert ascii to real value
CONVERT_HPA_TO_INHG_FIND_END
	lda  	,X+
	bne  	CONVERT_HPA_TO_INHG_FIND_END
	; do single digit
	lda  	,--X
	suba 	#'0'
	sta  	<hpaValue+1
	; do 10s digit
	lda  	,-X 
	suba 	#'0'
	ldb  	#10
	mul 
	addd 	<hpaValue
	std  	<hpaValue
	; do 100s digit
	lda  	,-X 
	suba 	#'0'
	ldb  	#100
	mul 
	addd 	<hpaValue
	std 	<hpaValue
	cmpx  	2,S 
	bls  	CONVERT_HPA_TO_INHG_GOT_VALUE
	; do 1000s digit if exists
	lda  	,-X 
	suba 	#'0'
	ldb  	#100
	mul 
	lda  	#10
	mul 
	addd 	<hpaValue
	std 	<hpaValue
CONVERT_HPA_TO_INHG_GOT_VALUE
*** HUGE THANKS to David Philipsen for writing this conversion routine!! ***
	ldd 	#0
	std 	v24h,U
	sta 	v24l,U 	; clear 24-bit accumulator
	ldd 	<hpaValue 	; get hPa value
	subd 	#1016 		; normalize to base of 1016
	std  	<hpaValue  	; (Todd) replace hpaValue with normalized number to use at the end
	std   	<tempWord 
	std 	v24m,U 	; add the value to accum (1x)
	bcc 	CONVERT_HPA_TO_INHG_NO_CARRY_SK0
	dec 	v24h,U
CONVERT_HPA_TO_INHG_NO_CARRY_SK0
	addd 	v24h,U 	; add the value to accum (256x)
	std 	v24h,U
	ldd 	<tempWord 	; get original value
	aslb
	rola  			; mult orig val by 2
	std 	<tempWord 	; save it
	addd 	v24h,U
	std 	v24h,U 	; add the value to accum (512x)
	ldd 	<tempWord
	aslb
	rola
	aslb
	rola
	std 	<tempWord 	; now shifted two more for 8x
	addd 	v24m,U
	std 	v24m,U 	; add the value to the accum (8x)
	ldd 	<tempWord
	addd 	v24h,U 	; add the value to accum (2048x)
	std 	v24h,U
	ldd 	<hpaValue
	asra
	rorb
	addd 	v24h,U
	std 	v24h,U 	; add the value to accum (128x)

	; total now  in accumulator is 2953x of the original value
       
	ldd 	#$C7EC 	; add in 3,000,300
	addd 	v24m,U
	std 	v24m,U
	bcc 	CONVERT_HPA_TO_INHG_NO_CARRY_SK4
	inc 	v24h,U
CONVERT_HPA_TO_INHG_NO_CARRY_SK4
	lda 	#$2D
	adda 	v24h,U
	sta 	v24h,U

	; convert result to ascii and copy to variable
	leax  	v24h,U 
	leay  	pressureInches,U 
	lbsr  	CONVERT_BINARY32_DECIMAL

	puls  	D,X,Y,PC 

; -------------------------------------
; convert 32 bit value to comma delimited decimal number 
; Entry: X = pointer to 24 bit value to convert
; 	Y = pointer to destination to write ASCII result 
; Exit:  
; -------------------------------------
CONVERT_BINARY32_DECIMAL
	pshs 	U,Y,X,D 

	leay 	,X 
	leax  	u32Value,U 	
	clr  	,X 
	lda  	,Y 
	sta  	1,X
	ldd 	1,Y 
	std 	2,X 
	
	ldu  	4,S   		; load ptr in Y on stack into U register 
	ldd  	#"00"
	std  	,U 
	std  	3,U 
	lda  	#'.'
	sta  	2,U 
	clr  	5,U 
	leay 	bin32dec1M,PCR 
CONVERT_BINARY32_DECIMAL_NEXT_1M
	lbsr 	SUBTRACT_32BIT
	bcs 	CONVERT_BINARY32_DECIMAL_DO_100K
	inc 	,U
	bra 	CONVERT_BINARY32_DECIMAL_NEXT_1M
CONVERT_BINARY32_DECIMAL_DO_100K
	lbsr 	ADD_32BIT
	leay 	bin32dec100K,PCR 
CONVERT_BINARY32_DECIMAL_NEXT_100K
	lbsr 	SUBTRACT_32BIT
	bcs 	CONVERT_BINARY32_DECIMAL_DO_10K
	inc 	1,U 
	bra 	CONVERT_BINARY32_DECIMAL_NEXT_100K
CONVERT_BINARY32_DECIMAL_DO_10K
	lbsr 	ADD_32BIT
	leay 	bin32dec10K,PCR 
CONVERT_BINARY32_DECIMAL_NEXT_10K
	lbsr 	SUBTRACT_32BIT
	bcs 	CONVERT_BINARY32_DECIMAL_DO_1K
	inc 	3,U 
	bra 	CONVERT_BINARY32_DECIMAL_NEXT_10K
CONVERT_BINARY32_DECIMAL_DO_1K
	lbsr 	ADD_32BIT
	ldd 	2,X 
CONVERT_BINARY32_DECIMAL_NEXT_1K
	subd 	#1000
	bcs 	CONVERT_BINARY32_DECIMAL_DO_100
	inc 	4,U 
	bra 	CONVERT_BINARY32_DECIMAL_NEXT_1K
CONVERT_BINARY32_DECIMAL_DO_100
	addd 	#1000
	clr 	<tempByte 
CONVERT_BINARY32_DECIMAL_NEXT_100
	subd 	#100
	bcs 	CONVERT_BINARY32_DECIMAL_DO_ROUNDING
	inc 	<tempByte 
	bra 	CONVERT_BINARY32_DECIMAL_NEXT_100
CONVERT_BINARY32_DECIMAL_DO_ROUNDING
	lda  	<tempByte
	cmpa  	#5 
	blo  	CONVERT_BINARY32_DECIMAL_DO_ROUNDING_DONE
	inc 	4,U 
	lda  	4,U 
	cmpa 	#'9'
	bls  	CONVERT_BINARY32_DECIMAL_DO_ROUNDING_DONE
	lda  	#'0'
	sta  	4,U 
	inc  	3,U 
	lda  	3,U 
	cmpa  	#'9'
	bls  	CONVERT_BINARY32_DECIMAL_DO_ROUNDING_DONE
	lda  	#'0'
	sta  	3,U 
	inc  	1,U 
	lda 	1,U 
	cmpa  	#'9'
	bls  	CONVERT_BINARY32_DECIMAL_DO_ROUNDING_DONE
	lda  	#'0'
	sta  	1,U 
	inc  	,U  	
CONVERT_BINARY32_DECIMAL_DO_ROUNDING_DONE

	puls 	D,X,Y,U,PC 

; -----------------------------------
; 32 bit subtraction 
; -----------------------------------
SUBTRACT_32BIT
      pshs  D
      ldd   2,X 
      subd  2,Y 
      std   2,X 
      ldd   ,X 
      sbcb  1,Y 
      sbca  ,Y 
      std   ,X 

      ; carry should be set properly now from subtract, now make sure zero flag works too
      ;ldd   ,X   ; not needed cuz previous instruction was STD ,X which already sets the Z and N flags 
      bne   SUBTRACT_32BIT_NOT_ZERO
      ldd   2,X
      andcc #%11110111 
SUBTRACT_32BIT_NOT_ZERO
      puls  D,PC 

 ;----------------------------------
 ; 32 bit addition 
 ; ---------------------------------
ADD_32BIT
      pshs  D 
      ldd   2,X 
      addd  2,Y 
      std   2,X 
      ldd   ,X 
      adcb  1,Y 
      adca  ,Y 
      std   ,X 

      bne   ADD_32BIT_NOT_ZERO
      ldd   2,X 
      andcc #%11110111
ADD_32BIT_NOT_ZERO
      puls  D,PC 

	include 	string_management.asm
	include  	graphics_management.asm
*************************************************************************************
	EMOD 
MODULE_SIZE 	; put this at the end so it can be used for module size 

