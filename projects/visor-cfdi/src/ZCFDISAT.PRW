#INCLUDE "PROTHEUS.CH"
#INCLUDE "TOPCONN.CH"

/*/{Protheus.doc} ZCFDISAT
Consulta del estatus de un CFDI ante el SAT.

POR QUE ESTO IMPORTA

Hoy el visor dice "sin consultar al SAT" y eso es honesto, pero no sirve
de mucho. Un CFDI puede estar CANCELADO por el emisor y tu copia del XML
ni se entera: el archivo no cambia. La unica fuente que sabe si un
comprobante sigue vivo es el SAT.

El unico "cancelado" que marca hoy el visor viene de que el archivo estaba
en una carpeta llamada ANULADAS. Eso es una convencion de la empresa, no
un dato fiscal.

COMO SE LE PREGUNTA AL SAT

El SAT publica un servicio (ConsultaCFDIService) donde se le manda un
texto con RFC emisor, RFC receptor, total y UUID, y contesta:

  Estado          Vigente / Cancelado / No Encontrado
  EsCancelable    si se puede cancelar y como
  EstatusCancelacion  en que va la cancelacion, si la hay

No pide certificados ni contrasenas. Es publico.

PERO PRIMERO: ALCANZA EL SERVIDOR AL SAT?

Este AppServer esta en la red de la empresa. Puede que no tenga salida a
internet, o que salga por un proxy. Si no alcanza al SAT, toda la consulta
sobra -- y es mejor saberlo en dos minutos que despues de escribirla.

Por eso esta rutina empieza siendo una PRUEBA DE CONEXION y nada mas. La
consulta de verdad se escribe cuando sepamos que hay por donde.

@author Claude + Miguel Yasec
@since 09/2026
/*/
User Function ZCFDISAT()
	Local nOpc := 0

	nOpc := Aviso("Estatus ante el SAT", ;
		"El SAT es la unica fuente que sabe si un CFDI sigue vivo." + CRLF + CRLF + ;
		"1. Uno        - un comprobante, con todo a la vista" + CRLF + ;
		"2. Formatos   - el mismo, con varias formas del total" + CRLF + ;
		"3. TODOS      - y guardar el resultado en el visor" + CRLF + CRLF + ;
		"(la prueba de conexion ya paso: el SAT contesta)", ;
		{"1. Uno", "2. Formatos", "3. Todos"})

	Do Case
	Case nOpc == 1 ; SatUno()
	Case nOpc == 2 ; SatForm()
	Case nOpc == 3 ; SatTodos()
	EndCase

Return

// ---------------------------------------------------------------------
Static Function SatConex()
	Local cMsg := ""

	If !MsgYesNo("Se va a intentar conectar al servicio del SAT." + CRLF + CRLF + ;
		"No manda datos de nadie: solo toca la puerta para ver" + CRLF + ;
		"si este servidor tiene salida." + CRLF + CRLF + ;
		"Continuar?", "ZCFDISAT")
		Return
	EndIf

	cMsg := "=== ALCANZA ESTE SERVIDOR AL SAT? ===" + CRLF + CRLF
	cMsg += "Se prueban varias direcciones. Basta con que UNA conteste" + CRLF
	cMsg += "para saber que hay salida." + CRLF + CRLF

	Processa({|| cMsg += SatPrue() }, "Tocando la puerta del SAT...")

	SatMues("Prueba de conexion al SAT", cMsg)

Return

// ---------------------------------------------------------------------
// 2) Uno solo, con todo a la vista.
//
// Antes de consultar 66 comprobantes conviene ver UNO completo: que se
// le mando, que contesto, y si lo entendimos bien. Si algo esta mal --
// el formato del total, un RFC vacio -- aqui se ve, y no despues de
// haber marcado 66 registros con un dato equivocado.
// ---------------------------------------------------------------------
Static Function SatUno()
	Local cMsg := ""
	Local aRes := {}

	If !SatAbre()
		Return
	EndIf

	// El primero que tenga con que preguntar.
	ZCF->(DbGoTop())
	Do While !ZCF->(Eof())
		If !Empty(AllTrim(ZCF->ZCF_UUID)) .And. ;
		   !Empty(AllTrim(ZCF->ZCF_EMIRFC)) .And. ;
		   !Empty(AllTrim(ZCF->ZCF_RECRFC))
			Exit
		EndIf
		ZCF->(DbSkip())
	EndDo

	If ZCF->(Eof())
		MsgStop("No hay ningun comprobante con RFC emisor, RFC receptor" + CRLF + ;
			"y folio fiscal. Sin esos tres no se le puede preguntar" + CRLF + ;
			"al SAT.", "ZCFDISAT")
		Return
	EndIf

	cMsg := "=== CONSULTA DE UN COMPROBANTE ===" + CRLF + CRLF
	cMsg += "Serie-folio : " + AllTrim(ZCF->ZCF_SERIE) + "-" + ;
	        AllTrim(ZCF->ZCF_FOLIO) + CRLF
	cMsg += "Folio fiscal: " + AllTrim(ZCF->ZCF_UUID) + CRLF
	cMsg += "Emisor      : " + AllTrim(ZCF->ZCF_EMIRFC) + CRLF
	cMsg += "Receptor    : " + AllTrim(ZCF->ZCF_RECRFC) + CRLF
	cMsg += "Total       : " + SatNum(ZCF->ZCF_TOTAL) + CRLF + CRLF

	aRes := SatCons(AllTrim(ZCF->ZCF_EMIRFC), ;
	                AllTrim(ZCF->ZCF_RECRFC), ;
	                ZCF->ZCF_TOTAL, ;
	                AllTrim(ZCF->ZCF_UUID), ;
	                @cMsg)

	cMsg += CRLF + "=== LO QUE CONTESTO EL SAT ===" + CRLF + CRLF
	cMsg += "Estado           : " + aRes[1] + CRLF
	cMsg += "Es cancelable    : " + aRes[2] + CRLF
	cMsg += "Estatus cancelac.: " + aRes[3] + CRLF
	cMsg += "Codigo           : " + aRes[4] + CRLF + CRLF

	If Empty(aRes[1])
		cMsg += "[!] No se pudo leer el estado. Arriba esta la respuesta" + CRLF
		cMsg += "    completa: hay que ver que contesto de verdad antes" + CRLF
		cMsg += "    de consultar los demas." + CRLF
	Else
		cMsg += "Si esto se ve bien, ya se puede correr la opcion 3." + CRLF
	EndIf

	SatMues("Consulta de un comprobante", cMsg)

Return

// ---------------------------------------------------------------------
// 2) El mismo comprobante, con varias formas del total.
//
// POR QUE ESTA PRUEBA EXISTE
//
// El SAT contesto "No Encontrado". Eso tiene DOS explicaciones que dan
// exactamente la misma respuesta, asi que no se pueden distinguir a ojo:
//
//   a) El timbre es de pruebas. Estamos en homologacion; si el XML se
//      timbro contra el ambiente de pruebas del PAC, nunca llego al SAT
//      real. No existe para el, y "No Encontrado" es lo correcto.
//
//   b) Le mandamos mal el total. El SAT es quisquilloso con el formato
//      de tt, y cuando no le cuadra NO dice "el total esta mal": dice
//      "No Encontrado". Identico.
//
// Se separan cambiando UNA sola cosa: el formato del total, sobre el
// mismo comprobante. Si alguna forma contesta distinto, el problema era
// nuestro. Si todas contestan igual, el formato queda descartado y lo
// que queda son los timbres de prueba.
//
// Esto no prueba (b) falso de manera absoluta -- podria ser que ninguna
// de las formas que probamos sea la buena. Pero si las descarta como
// explicacion probable, que es lo que se necesita para seguir.
// ---------------------------------------------------------------------
Static Function SatForm()
	Local cMsg  := ""
	Local cNada := ""
	Local aFor  := {}
	Local aRes  := {}
	Local nI    := 0
	Local cEmi  := ""
	Local cRec  := ""
	Local cUui  := ""
	Local nTot  := 0
	Local cDis  := ""

	If !SatAbre()
		Return
	EndIf

	ZCF->(DbGoTop())
	Do While !ZCF->(Eof())
		If !Empty(AllTrim(ZCF->ZCF_UUID)) .And. ;
		   !Empty(AllTrim(ZCF->ZCF_EMIRFC)) .And. ;
		   !Empty(AllTrim(ZCF->ZCF_RECRFC))
			Exit
		EndIf
		ZCF->(DbSkip())
	EndDo

	If ZCF->(Eof())
		MsgStop("No hay un comprobante con los tres datos.", "ZCFDISAT")
		Return
	EndIf

	cEmi := AllTrim(ZCF->ZCF_EMIRFC)
	cRec := AllTrim(ZCF->ZCF_RECRFC)
	cUui := AllTrim(ZCF->ZCF_UUID)
	nTot := ZCF->ZCF_TOTAL

	// Las formas que el SAT ha aceptado a lo largo del tiempo.
	AAdd(aFor, {"tal cual, 2 decimales", AllTrim(Str(nTot, 20, 2))})
	AAdd(aFor, {"6 decimales",           AllTrim(Str(nTot, 24, 6))})
	AAdd(aFor, {"18 enteros + 6 dec",    StrZero(Int(nTot), 18) + "." + ;
	            StrZero(Int((nTot - Int(nTot)) * 1000000), 6)})
	AAdd(aFor, {"10 enteros + 2 dec",    StrZero(Int(nTot), 10) + "." + ;
	            StrZero(Int(Round((nTot - Int(nTot)) * 100, 0)), 2)})

	cMsg := "=== EL MISMO COMPROBANTE, VARIOS FORMATOS ===" + CRLF + CRLF
	cMsg += "Folio fiscal: " + cUui + CRLF
	cMsg += "Emisor      : " + cEmi + CRLF
	cMsg += "Receptor    : " + cRec + CRLF
	cMsg += "Total real  : " + AllTrim(Str(nTot, 20, 2)) + CRLF + CRLF
	cMsg += "Solo cambia el formato del total. Todo lo demas es igual." + CRLF + CRLF

	For nI := 1 To Len(aFor)

		aRes := SatCons(cEmi, cRec, nTot, cUui, @cNada, aFor[nI][2])

		cMsg += "-- " + PadR(aFor[nI][1], 22) + " tt=" + aFor[nI][2] + CRLF
		cMsg += "   Estado : " + IIf(Empty(aRes[1]), "(sin respuesta)", aRes[1]) + CRLF
		cMsg += "   Codigo : " + SubStr(aRes[4], 1, 55) + CRLF + CRLF

		If nI == 1
			cDis := aRes[1]
		ElseIf aRes[1] != cDis
			cDis := "DISTINTO"
		EndIf

	Next nI

	cMsg += "=== QUE QUIERE DECIR ===" + CRLF + CRLF

	If cDis == "DISTINTO"
		cMsg += "Los formatos NO dan lo mismo. Entonces el formato SI" + CRLF
		cMsg += "importaba y estabamos preguntando mal. Hay que quedarse" + CRLF
		cMsg += "con el que contesto distinto y usar ese para todos." + CRLF
	Else
		cMsg += "Los " + cValToChar(Len(aFor)) + " formatos contestan lo mismo." + CRLF + CRLF
		cMsg += "El formato del total queda DESCARTADO como explicacion." + CRLF
		cMsg += "Lo que queda es que estos timbres no existen para el SAT," + CRLF
		cMsg += "que es justo lo que uno esperaria de un ambiente de" + CRLF
		cMsg += "homologacion: se timbraron contra el PAC de pruebas." + CRLF + CRLF
		cMsg += "OJO: esto no prueba que el formato sea correcto. Prueba" + CRLF
		cMsg += "que no es LA DIFERENCIA aqui. La consulta solo se puede" + CRLF
		cMsg += "validar de verdad contra un CFDI que si exista en el SAT," + CRLF
		cMsg += "o sea en Produccion." + CRLF
	EndIf

	SatMues("Formatos del total", cMsg)

Return

// ---------------------------------------------------------------------
// 3) Todos, guardando el resultado.
//
// OJO: esto SI escribe. Sobrescribe ZCF_ESTSAT, incluido el "C" que
// pusimos por estar el archivo en la carpeta ANULADAS. Y esta bien que
// lo sobrescriba: esa carpeta es una costumbre de la empresa, el SAT es
// el dato fiscal. Lo que diga el SAT gana.
// ---------------------------------------------------------------------
Static Function SatTodos()
	Local cMsg := ""
	Local cNada := ""
	Local aRes := {}
	Local nTot := 0
	Local nVig := 0
	Local nCan := 0
	Local nNoE := 0
	Local nErr := 0
	Local nSin := 0
	Local cEst := ""

	If !SatAbre()
		Return
	EndIf

	If !MsgYesNo("Se va a consultar al SAT comprobante por comprobante" + CRLF + ;
		"y GUARDAR el resultado en el visor." + CRLF + CRLF + ;
		"Esto sobrescribe el estatus actual, incluido el cancelado" + CRLF + ;
		"que venia de la carpeta ANULADAS. Gana lo que diga el SAT." + CRLF + CRLF + ;
		"Son " + cValToChar(ZCF->(LastRec())) + " comprobantes. Continuar?", ;
		"ZCFDISAT")
		Return
	EndIf

	ZCF->(DbGoTop())
	Do While !ZCF->(Eof())

		If Empty(AllTrim(ZCF->ZCF_UUID)) .Or. ;
		   Empty(AllTrim(ZCF->ZCF_EMIRFC)) .Or. ;
		   Empty(AllTrim(ZCF->ZCF_RECRFC))
			nSin++
			ZCF->(DbSkip())
			Loop
		EndIf

		nTot++

		aRes := SatCons(AllTrim(ZCF->ZCF_EMIRFC), ;
		                AllTrim(ZCF->ZCF_RECRFC), ;
		                ZCF->ZCF_TOTAL, ;
		                AllTrim(ZCF->ZCF_UUID), ;
		                @cNada)

		cEst := ""
		Do Case
		Case "Vigente"   $ aRes[1] ; cEst := "V" ; nVig++
		Case "Cancelado" $ aRes[1] ; cEst := "C" ; nCan++
		Case "No Encontrado" $ aRes[1] ; cEst := "N" ; nNoE++
		Otherwise                  ; nErr++
		EndCase

		If !Empty(cEst)
			RecLock("ZCF", .F.)
			ZCF->ZCF_ESTSAT := cEst
			ZCF->ZCF_MOTIVO := SubStr(AllTrim(aRes[1]) + " / " + ;
			                          AllTrim(aRes[3]), 1, 250)
			ZCF->(MsUnlock())
		EndIf

		ZCF->(DbSkip())
	EndDo

	cMsg := "=== CONSULTA AL SAT: RESULTADO ===" + CRLF + CRLF
	cMsg += "Consultados     : " + cValToChar(nTot) + CRLF + CRLF
	cMsg += "  Vigentes      : " + cValToChar(nVig) + CRLF
	cMsg += "  CANCELADOS    : " + cValToChar(nCan) + CRLF
	cMsg += "  No encontrados: " + cValToChar(nNoE) + CRLF
	cMsg += "  Sin respuesta : " + cValToChar(nErr) + CRLF + CRLF
	cMsg += "Sin datos para preguntar: " + cValToChar(nSin) + CRLF + CRLF

	If nNoE > 0
		cMsg += "[!] " + cValToChar(nNoE) + " NO ENCONTRADO(S)." + CRLF
		cMsg += "    Eso es grave: el SAT no conoce ese folio fiscal." + CRLF
		cMsg += "    O el XML no corresponde a un CFDI real, o el total" + CRLF
		cMsg += "    o los RFC que le mandamos no son los del timbre." + CRLF
		cMsg += "    Revisar esos antes de sacar conclusiones." + CRLF + CRLF
	EndIf

	If nErr > 0
		cMsg += "[!] " + cValToChar(nErr) + " sin respuesta. Esos NO se" + CRLF
		cMsg += "    tocaron: conservan el estatus que ya tenian." + CRLF + CRLF
	EndIf

	cMsg += "Abre el visor para verlos. Los cancelados salen en rojo." + CRLF

	SatMues("Consulta al SAT", cMsg)

Return

// ---------------------------------------------------------------------
// La consulta. Devuelve {estado, esCancelable, estatusCancelacion, codigo}
//
// El SAT pide los cuatro datos en un solo texto, el mismo que va en el
// codigo QR de la factura impresa. De ahi el nombre "expresion impresa".
// ---------------------------------------------------------------------
Static Function SatCons(cEmi, cRec, nTot, cUuid, cLog, cTotFor)
	Local aRet  := {"", "", "", ""}
	Local cUrl  := "https://consultaqr.facturaelectronica.sat.gob.mx/ConsultaCFDIService.svc"
	Local cExpr := ""
	Local cSoap := ""
	Local cResp := ""
	Local aHead := {}
	Local cHead := ""

	// cTotFor permite forzar un formato del total, para la prueba de
	// formatos. Cuando no viene, se usa el de siempre.
	cExpr := "?re=" + cEmi
	cExpr += "&rr=" + cRec
	cExpr += "&tt=" + IIf(cTotFor == NIL, SatNum(nTot), cTotFor)
	cExpr += "&id=" + cUuid

	cSoap := '<?xml version="1.0" encoding="UTF-8"?>'
	cSoap += '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"'
	cSoap += ' xmlns:t="http://tempuri.org/">'
	cSoap += '<s:Header/><s:Body><t:Consulta>'
	cSoap += '<t:expresionImpresa><![CDATA[' + cExpr + ']]></t:expresionImpresa>'
	cSoap += '</t:Consulta></s:Body></s:Envelope>'

	AAdd(aHead, 'Content-Type: text/xml; charset=utf-8')
	AAdd(aHead, 'SOAPAction: "http://tempuri.org/IConsultaCFDIService/Consulta"')

	If cLog != NIL
		cLog += "=== LO QUE SE LE MANDO ===" + CRLF + CRLF
		cLog += cExpr + CRLF + CRLF
	EndIf

	cResp := HttpPost(cUrl, "", cSoap, 30, aHead, @cHead)

	If cResp == NIL .Or. Empty(cResp)
		If cLog != NIL
			cLog += "[!] sin respuesta del servicio" + CRLF
			If !Empty(cHead)
				cLog += "    " + SubStr(SatLimp(cHead), 1, 200) + CRLF
			EndIf
		EndIf
		Return aRet
	EndIf

	If cLog != NIL
		cLog += "=== RESPUESTA CRUDA ===" + CRLF + CRLF
		cLog += SubStr(SatLimp(cResp), 1, 900) + CRLF
	EndIf

	aRet[1] := SatVal(cResp, "Estado")
	aRet[2] := SatVal(cResp, "EsCancelable")
	aRet[3] := SatVal(cResp, "EstatusCancelacion")
	aRet[4] := SatVal(cResp, "CodigoEstatus")

Return aRet

// ---------------------------------------------------------------------
// Saca el contenido de una etiqueta, sin importar el prefijo de espacio
// de nombres que traiga (a:Estado, ns2:Estado, Estado...).
// ---------------------------------------------------------------------
Static Function SatVal(cTxt, cTag)
	Local nIni := 0
	Local nFin := 0

	nIni := At(cTag + ">", cTxt)
	If nIni == 0
		Return ""
	EndIf

	nIni += Len(cTag) + 1

	nFin := At("<", SubStr(cTxt, nIni))
	If nFin == 0
		Return ""
	EndIf

Return AllTrim(SubStr(cTxt, nIni, nFin - 1))

// ---------------------------------------------------------------------
// El total, como lo espera el SAT: punto decimal, sin separador de
// miles, sin signo de moneda.
// ---------------------------------------------------------------------
Static Function SatNum(nVal)
Return AllTrim(Str(nVal, 20, 2))

// ---------------------------------------------------------------------
Static Function SatAbre()

	If Select("ZCF") == 0
		ChkFile("ZCF")
	EndIf
	If Select("ZCF") == 0
		MsgStop("No se pudo abrir ZCF.", "ZCFDISAT")
		Return .F.
	EndIf

	If ZCF->(LastRec()) == 0
		MsgInfo("No hay comprobantes cargados." + CRLF + CRLF + ;
			"Corre primero Construir - Importar XML.", "ZCFDISAT")
		Return .F.
	EndIf

Return .T.

// ---------------------------------------------------------------------
// Las pruebas, de la mas basica a la que de verdad nos interesa.
// ---------------------------------------------------------------------
Static Function SatPrue()
	Local cRet := ""

	// 1) Algo conocido y estable, para separar "no hay internet" de
	//    "el SAT no contesta". Si esto falla, el problema es la red.
	cRet += SatUna("Internet en general", ;
		"https://www.google.com")

	// 2) El portal del SAT. Si contesta, hay salida hacia el SAT.
	cRet += SatUna("Portal del SAT", ;
		"https://www.sat.gob.mx")

	// 3) El servicio de consulta. Este es el que necesitamos.
	cRet += SatUna("Servicio de consulta CFDI", ;
		"https://consultaqr.facturaelectronica.sat.gob.mx/ConsultaCFDIService.svc")

	// 4) El mismo servicio pidiendo su WSDL, que es como se averigua
	//    que operaciones expone.
	cRet += SatUna("WSDL del servicio", ;
		"https://consultaqr.facturaelectronica.sat.gob.mx/ConsultaCFDIService.svc?wsdl")

	cRet += CRLF + "=== COMO LEER ESTO ===" + CRLF + CRLF
	cRet += "Todo falla         -> el servidor no sale a internet." + CRLF
	cRet += "                      Hay que pedirle salida a sistemas," + CRLF
	cRet += "                      o correr la consulta desde otro lado." + CRLF + CRLF
	cRet += "Google si, SAT no  -> hay internet pero el SAT esta bloqueado" + CRLF
	cRet += "                      o filtrado. Es permiso, no red." + CRLF + CRLF
	cRet += "El WSDL contesta   -> se puede escribir la consulta. Es lo" + CRLF
	cRet += "                      que estamos buscando." + CRLF

Return cRet

// ---------------------------------------------------------------------
// Una prueba. Se reporta lo que pase, incluido el error.
// ---------------------------------------------------------------------
Static Function SatUna(cQue, cUrl)
	Local cRet  := ""
	Local cResp := ""
	Local aHead := {}
	Local cHead := ""
	Local nSeg  := 0

	cRet := "-- " + cQue + CRLF
	cRet += "   " + SubStr(cUrl, 1, 62) + CRLF

	nSeg := Seconds()

	cResp := HttpGet(cUrl, "", 20, aHead, @cHead)

	nSeg := Seconds() - nSeg

	If cResp == NIL .Or. Empty(cResp)
		cRet += "   [NO] sin respuesta"
		cRet += "   (" + AllTrim(Transform(nSeg, "@E 999.9")) + "s)" + CRLF
		If !Empty(cHead)
			cRet += "   cabecera: " + SubStr(AllTrim(cHead), 1, 60) + CRLF
		EndIf
	Else
		cRet += "   [SI] contesto " + cValToChar(Len(cResp)) + " bytes"
		cRet += "   (" + AllTrim(Transform(nSeg, "@E 999.9")) + "s)" + CRLF
		cRet += "   " + SubStr(SatLimp(cResp), 1, 60) + CRLF
	EndIf

Return cRet + CRLF

// ---------------------------------------------------------------------
// Deja la respuesta en una sola linea, para poder mirarla de reojo.
// ---------------------------------------------------------------------
Static Function SatLimp(cTxt)
	Local cRet := AllTrim(cTxt)

	cRet := StrTran(cRet, CRLF, " ")
	cRet := StrTran(cRet, Chr(13), " ")
	cRet := StrTran(cRet, Chr(10), " ")
	cRet := StrTran(cRet, Chr(9),  " ")

	Do While "  " $ cRet
		cRet := StrTran(cRet, "  ", " ")
	EndDo

Return AllTrim(cRet)

// ---------------------------------------------------------------------
// Ventana de solo lectura con texto desplazable.
//
// OJO: no usar cVer como nombre de variable, choca con el framework.
// ---------------------------------------------------------------------
Static Function SatMues(cTitulo, cTexto)
	Local oDlg  := NIL
	Local oMem  := NIL
	Local cMemo := cTexto

	DEFINE MSDIALOG oDlg TITLE cTitulo FROM 0, 0 TO 500, 750 PIXEL

	@ 5, 5 GET oMem VAR cMemo MEMO SIZE 365, 225 OF oDlg PIXEL
	oMem:bWhen := {|| .F. }

	@ 235, 320 BUTTON "Ok" SIZE 40, 12 OF oDlg PIXEL ACTION oDlg:End()

	ACTIVATE MSDIALOG oDlg CENTERED

Return
