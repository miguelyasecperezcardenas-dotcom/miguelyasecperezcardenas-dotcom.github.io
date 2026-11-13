#INCLUDE "PROTHEUS.CH"
#INCLUDE "TOPCONN.CH"

// Los RFC de la casa, armados una sola vez por sesion. NIL = todavia
// no se han buscado; un arreglo vacio significa que se busco y no se
// encontro nada, que no es lo mismo.
Static _aRfcCasa := NIL

/*/{Protheus.doc} ZCFDIIMP
Ingesta de los XML de CFDI hacia ZCF, ZCC, ZCI, ZCP y ZCR.

DOS MODOS

  1. PROBAR EL PARSER  - lee UN archivo y reporta que extrajo. No graba.
  2. IMPORTAR          - recorre las carpetas y carga todo.

El modo 1 existe porque es la primera vez que este proyecto usa
XmlParser. Antes de meter 195 archivos a la base conviene ver que el
parser devuelve lo que se espera sobre un archivo real. Descubrir una
mania del parser con la base vacia sale mucho mas barato que a la mitad
de una carga.

REGLAS DE INGESTA, YA DECIDIDAS

  - Se ignoran los archivos *_ORIGIN*: son la copia previa al timbrado,
    el mismo comprobante duplicado sin UUID.
  - Solo entran a ZCF los comprobantes CON timbre. Los que no lo traen
    se registran en ZCR con estado 'S', para que quede constancia de que
    el archivo estaba ahi sin ensuciar el acervo fiscal.
  - Antes de insertar se busca el UUID en ZCF. Si ya esta, se salta. Asi
    la rutina se puede correr cuantas veces se quiera.
  - Un archivo que truene no detiene la carga: se anota y se sigue con
    el siguiente. Con 195 archivos, morirse en el 12 seria inutil.

NODOS REPETIDOS: LA TRAMPA DEL PARSER

XmlParser devuelve un OBJETO cuando un nodo aparece una sola vez, y un
ARREGLO cuando aparece varias. Una factura de un solo concepto y una de
tres se leen distinto.

Por eso todo pasa por ImpArr(), que normaliza las dos formas a arreglo.
Es el error clasico de esta parte y no se ve hasta que llega la primera
factura con mas de un renglon.

@author Claude + Miguel Yasec
@since 09/2026
/*/
User Function ZCFDIIMP()
	Local nOpc  := 0
	Local lVac  := .F.
	Local nTope := 0

	nOpc := Aviso("ZCFDIIMP - Ingesta de XML", ;
		"Carga los XML de CFDI a las tablas del visor." + CRLF + CRLF + ;
		"Archivo : sube UN xml de TU maquina y lo carga al visor." + CRLF + ;
		"Importar: recorre las carpetas del servidor y carga todo." + CRLF + ;
		"Vaciar  : deja el visor en blanco, sin cargar nada." + CRLF + CRLF + ;
		"Para salir, cierra la ventana.", ;
		{"Un archivo mio", "Importar todo", "Vaciar el visor"}, 3)

	Do Case
	Case nOpc == 1
		ImpMio()
	Case nOpc == 3
		ImpSolo()
	Case nOpc == 2
		If MsgYesNo("Importar todos los XML a las tablas?" + CRLF + CRLF + ;
			"Lo que ya este cargado se salta por UUID," + CRLF + ;
			"asi que no se duplica nada.", "ZCFDIIMP")

			// Una corrida que trueno a la mitad puede dejar un
			// comprobante incompleto. Como el UUID ya estaria ahi, la
			// siguiente corrida lo saltaria y el hueco quedaria escondido.
			lVac := MsgYesNo("Vaciar las tablas antes de importar?" + CRLF + CRLF + ;
				"Contesta SI si una corrida anterior trono a la mitad:" + CRLF + ;
				"un comprobante incompleto se saltaria por UUID y el" + CRLF + ;
				"hueco no se notaria." + CRLF + CRLF + ;
				"Solo borra ZCF, ZCC, ZCI, ZCP y ZCR. Los XML del" + CRLF + ;
				"servidor no se tocan, asi que todo se puede rearmar.", ;
				"ZCFDIIMP - vaciar")

			nTope := ImpTope()

			// -1 es que cerro la ventana del tope: no preguntar dos
			// veces ni arrancar una corrida que no pidio.
			If nTope >= 0
				Processa({|| ImpTodo(lVac, nTope) }, "Importando...")
			EndIf
		EndIf
	EndCase

Return

// =====================================================================
// CUANTOS COMPROBANTES CARGAR DE UNA CORRIDA
//
// "Importar todo" era todo o nada. Contra un acervo que nadie ha leido
// eso es apostar a ciegas: si el parser se atraganta con un tipo de
// comprobante que no se ha probado, uno se entera despues de horas y
// con las tablas a medio llenar.
//
// EL TOPE CUENTA COMPROBANTES NUEVOS, NO ARCHIVOS LEIDOS
//
// Esa distincion es la que hace que las corridas se encadenen solas.
// Lo que ya entro se salta por UUID sin gastar tope, asi que correr 50
// y luego 500 carga 450 mas -- no vuelve a empezar desde el primero.
// =====================================================================
Static Function ImpTope()
	Local nOpc := 0

	// El mensaje va largo a proposito: Aviso dimensiona la ventana por
	// el texto, y si no cabe se lleva los botones a un desplegable.
	nOpc := Aviso("ZCFDIIMP - cuantos", ;
		"Cuantos comprobantes NUEVOS cargar en esta corrida?" + CRLF + CRLF + ;
		"  50   : la primera vez contra un acervo que no se ha leido." + CRLF + ;
		"  500  : cuando los primeros 50 entraron limpios." + CRLF + ;
		"  Todo : cuando ya se sabe que aguanta." + CRLF + CRLF + ;
		"Lo que ya esta cargado se salta por UUID y no gasta tope, asi" + CRLF + ;
		"que las corridas se encadenan: 50 y despues 500 carga 450 mas.", ;
		{"50", "500", "Todo"}, 3)

	Do Case
	Case nOpc == 1 ; Return 50
	Case nOpc == 2 ; Return 500
	Case nOpc == 3 ; Return 0     // sin tope
	EndCase

Return -1    // cerro la ventana

// =====================================================================
// MODO 1: PROBAR EL PARSER
// =====================================================================
Static Function ImpTest()
	Local aCar := {}
	Local aArq := {}
	Local cArq := ""
	Local cTxt := ""
	Local cRep := ""
	Local nI   := 0

	ImpCarp(@aCar)

	If Len(aCar) == 0
		MsgStop("No se encontro ninguna carpeta con XML.", "ZCFDIIMP")
		Return
	EndIf

	// buscar el primer archivo util: timbrado y que no sea _ORIGIN
	For nI := 1 To Len(aCar)
		aArq := Directory(aCar[nI] + "*.xml")
		cArq := ImpBuena(aCar[nI], aArq)
		If !Empty(cArq)
			Exit
		EndIf
	Next nI

	If Empty(cArq)
		MsgStop("No se encontro ningun XML timbrado para probar.", "ZCFDIIMP")
		Return
	EndIf

	cTxt := MemoRead(cArq)

	cRep := "--- PRUEBA DEL PARSER ---" + CRLF + CRLF
	cRep += "Archivo: " + cArq + CRLF
	cRep += "Tamano : " + cValToChar(Len(cTxt)) + " caracteres" + CRLF + CRLF

	cRep += ImpLee(cTxt, .T.)

	MsgInfo(cRep, "ZCFDIIMP - prueba")

Return

// ---------------------------------------------------------------------
// Primer archivo de la carpeta que sirva: timbrado y no _ORIGIN
// ---------------------------------------------------------------------
Static Function ImpBuena(cRuta, aArq)
	Local nI   := 0
	Local cNom := ""
	Local cTxt := ""

	For nI := 1 To Len(aArq)
		cNom := AllTrim(aArq[nI][1])

		If "_ORIGIN" $ Upper(cNom)
			Loop
		EndIf

		cTxt := MemoRead(cRuta + cNom)
		If "TIMBREFISCALDIGITAL" $ Upper(cTxt)
			Return cRuta + cNom
		EndIf
	Next nI

Return ""

// =====================================================================
// MODO 2: IMPORTAR TODO
// =====================================================================
Static Function ImpTodo(lVac, nTope)
	Local aCar  := {}
	Local aArq  := {}
	Local nI    := 0
	Local nJ    := 0
	Local cNom  := ""
	Local cTxt  := ""
	Local cUuid := ""
	Local cMsg  := ""
	Local nLei  := 0
	Local nIns  := 0
	Local nDup  := 0
	Local nSin  := 0
	Local nOri  := 0
	Local nErr  := 0
	Local nFil  := 0
	Local nCan  := 0
	Local cSqlMs:= ""
	Local cFalla:= ""
	Local lTope := .F.

	Default nTope := 0

	_ImpLimpia()

	If !ImpAbre()
		Return
	EndIf

	If lVac == .T.
		ImpVacia()
	EndIf

	ImpCarp(@aCar)

	For nI := 1 To Len(aCar)
		aArq := Directory(aCar[nI] + "*.xml")
		ProcRegua(Len(aArq))

		For nJ := 1 To Len(aArq)
			IncProc()
			cNom := AllTrim(aArq[nJ][1])

			// los _ORIGIN son el mismo comprobante antes de timbrar
			If "_ORIGIN" $ Upper(cNom)
				nOri++
				Loop
			EndIf

			cTxt := MemoRead(aCar[nI] + cNom)
			If Empty(cTxt)
				nErr++
				Loop
			EndIf

			nLei++

			// sin timbre no entra al acervo: queda la constancia en ZCR
			//
			// Ademas se anota el detalle para el reporte del final. La
			// pregunta que importa no es cuantos hay, es CUALES y en
			// que paso se quedaron: un XML sin timbre PERO CON Sello ya
			// paso por el certificado de la empresa y solo le falto la
			// respuesta del PAC. Uno sin sello ni siquiera llego ahi.
			// Son dos problemas distintos y se arreglan en lugares
			// distintos, asi que contarlos juntos no sirve de nada.
			If !("TIMBREFISCALDIGITAL" $ Upper(cTxt))
				nSin++
				nFil++
				ImpZCR("", "XML", "   ", StrZero(nFil, 9), "S", ;
					"Archivo sin timbre: " + cNom)
				_ImpSinAn(cNom, aCar[nI], cTxt)
				Loop
			EndIf

			cUuid := Upper(ImpStr(cTxt, "UUID"))
			If Empty(cUuid)
				nErr++
				nFil++
				ImpZCR("", "XML", "   ", StrZero(nFil, 9), "E", ;
					"Trae timbre pero no se leyo el UUID: " + cNom)
				Loop
			EndIf

			// El mismo UUID en dos carpetas no es basura: si la segunda
			// copia esta en ANULADAS, ese comprobante se cancelo. Antes
			// se saltaba el archivo y con el se perdia ese dato.
			If ImpHayUu(cUuid)
				nDup++
				If ImpEsAnu(aCar[nI]) .And. ImpCanc(cUuid)
					nCan++
				EndIf
				Loop
			EndIf

			cFalla := ""
			If ImpUno(cTxt, cNom, aCar[nI], cUuid, @cFalla)
				nIns++

				If nTope > 0 .And. nIns >= nTope
					lTope := .T.
					Exit
				EndIf
			Else
				nErr++
				nFil++
				ImpZCR(cUuid, "XML", "   ", StrZero(nFil, 9), "E", cFalla)
			EndIf
		Next nJ

		// El tope corta la carpeta Y el recorrido: salir del For de
		// adentro no basta, seguiria con la siguiente carpeta.
		If lTope
			Exit
		EndIf
	Next nI

	// Los campos que el alias no supo escribir se guardan aqui, por SQL
	// directo, ya que todos los MsUnlock pasaron.
	cSqlMs := _ImpSqlFl()

	cMsg := "--- IMPORTACION TERMINADA ---" + CRLF + CRLF
	cMsg += "  Archivos leidos        : " + cValToChar(nLei) + CRLF
	cMsg += "  Comprobantes cargados  : " + cValToChar(nIns) + CRLF
	cMsg += "  Copias del mismo UUID  : " + cValToChar(nDup) + CRLF
	cMsg += "  Sin timbre (a ZCR)     : " + cValToChar(nSin) + CRLF
	cMsg += "  Marcados cancelados    : " + cValToChar(nCan) + CRLF
	cMsg += "  _ORIGIN ignorados      : " + cValToChar(nOri) + CRLF
	cMsg += "  Con problema           : " + cValToChar(nErr) + CRLF

	If nSin > 0
		cMsg += CRLF + _ImpSinRep() + CRLF
	EndIf

	// La etiqueta vieja decia "Ya estaban (por UUID)", que se lee como
	// "venian de una corrida anterior" y manda a vaciar las tablas sin
	// necesidad. Lo que cuenta son archivos que repiten un UUID YA
	// LEIDO EN ESTA MISMA CORRIDA: el mismo CFDI guardado en dos
	// carpetas. Vaciar no cambia ese numero.
	// Un campo que el parser leyo del XML y no pudo guardar es un hueco
	// silencioso. Casi siempre significa que la sesion de Protheus se
	// abrio ANTES de crear el campo: el diccionario se lee al abrir.
	If Len(_ImpFaltan()) > 0
		cMsg += CRLF
		cMsg += "NOTA: esta sesion no ve estos campos:" + CRLF
		For nI := 1 To Len(_ImpFaltan())
			cMsg += "   " + _ImpFaltan()[nI] + CRLF
		Next nI
		cMsg += CRLF
		cMsg += "Es que la sesion se abrio ANTES de que se crearan:" + CRLF
		cMsg += "Protheus lee el diccionario al abrir la sesion." + CRLF
		cMsg += "El dato NO se perdio: se escribio por SQL directo." + CRLF
		cMsg += cSqlMs
		cMsg += "Aun asi conviene reiniciar para que el visor los muestre." + CRLF
	EndIf

	If nDup > 0
		cMsg += CRLF
		cMsg += "Las " + cValToChar(nDup) + " copias son archivos con un UUID que ya" + CRLF
		cMsg += "se leyo en ESTA corrida: el mismo CFDI guardado en dos" + CRLF
		cMsg += "carpetas. No son comprobantes que falten, y vaciar las" + CRLF
		cMsg += "tablas no cambia ese numero." + CRLF
		cMsg += "Comprobantes distintos en el visor: " + cValToChar(nIns) + "." + CRLF
	EndIf

	If lTope
		cMsg += CRLF
		cMsg += "Se paro al llegar al tope de " + cValToChar(nTope) + "." + CRLF
		cMsg += "Quedan archivos sin leer. Vuelve a correr Importar todo" + CRLF
		cMsg += "para cargar los siguientes: los de esta corrida ya no" + CRLF
		cMsg += "se vuelven a procesar." + CRLF
	EndIf

	MsgInfo(cMsg, "ZCFDIIMP - resultado")

Return

/*/{Protheus.doc} ZCFDIUNO
Sube UN xml de la maquina del usuario. Se llama desde el boton
"Importar" del visor.

POR QUE EXISTE APARTE

Importar un archivo suelto es una operacion de todos los dias: llega
una factura de un proveedor por correo y alguien la quiere ver. Eso
pertenece al visor, junto a Detalle y Exportar.

Lo que NO sube al visor es "Importar todo" ni "Vaciar": esos tocan el
acervo completo y se quedan en Herramientas, que es donde el usuario
espera encontrar las cosas que hay que pensar dos veces.
/*/
User Function ZCFDIUNO()
Return ImpMio()

// =====================================================================
// VACIAR SIN CARGAR
//
// "Vaciar" existia nada mas adentro de Importar todo: se vaciaba y
// enseguida se volvia a cargar la carpeta del servidor, asi que no habia
// forma de dejar el visor en blanco. Para probar con archivos escogidos
// a mano hace falta justo eso -- si los tres archivos de prueba estan
// solos, cualquier cosa rara salta a la vista.
//
// Solo toca las cinco tablas del visor. Los XML del servidor no se
// mueven, asi que el acervo se rearma corriendo Importar todo.
// =====================================================================
Static Function ImpSolo()

	If !ImpAbre()
		Return
	EndIf

	If !MsgYesNo("Vaciar las cinco tablas del visor?" + CRLF + CRLF + ;
		"Quedan en blanco: ZCF, ZCC, ZCI, ZCP y ZCR." + CRLF + ;
		"Hoy hay " + cValToChar(ZCF->(LastRec())) + " comprobante(s)." + CRLF + CRLF + ;
		"Los XML del servidor NO se tocan, asi que todo se puede" + CRLF + ;
		"volver a cargar con Importar todo.", "ZCFDIIMP - vaciar")
		Return
	EndIf

	Processa({|| ImpVacia() }, "Vaciando...")

	MsgInfo("Listo. El visor quedo en blanco." + CRLF + CRLF + ;
		"Ahora puedes meterle archivos escogidos con 'Un archivo mio'," + CRLF + ;
		"o recargar todo el acervo con 'Importar todo'.", "ZCFDIIMP")

Return

// =====================================================================
// MODO 3: UN ARCHIVO DE LA MAQUINA DEL USUARIO
//
// La importacion normal lee la carpeta del servidor, y eso sirve para
// cargar el acervo. Pero para PROBAR el visor uno quiere meterle un
// comprobante escogido a proposito -- uno cancelado, uno con retenciones,
// uno raro -- sin tener que dejarlo en la carpeta de nadie.
//
// El archivo se sube al servidor (CpyT2S), se carga, y ya. Se aplican
// las mismas reglas que la importacion normal: sin timbre no entra, y
// si el UUID ya esta no se duplica.
// =====================================================================
Static Function ImpMio()
	Local cCli  := ""
	Local cNom  := ""
	Local cSrv  := ""
	Local cTxt  := ""
	Local cUuid := ""
	Local cFalla := ""
	Local cMsg  := ""
	Local nPos  := 0

	If !ImpAbre()
		Return
	EndIf

	cCli := cGetFile("Archivo XML|*.xml|Todos|*.*", "Escoge el XML", ;
		0, "C:\", .F., GETF_LOCALHARD + GETF_NETWORKDRIVE, .F., .T.)

	If Empty(cCli)
		Return
	EndIf

	// El nombre, sin la ruta.
	cNom := cCli
	Do While (nPos := At("\", cNom)) > 0
		cNom := SubStr(cNom, nPos + 1)
	EndDo

	// CpyT2S sube de la maquina del usuario al servidor. El destino es
	// una CARPETA, igual que CpyS2T -- conserva el nombre del origen.
	If !CpyT2S(cCli, "\system\")
		MsgStop("No se pudo subir el archivo al servidor." + CRLF + CRLF + ;
			"Revisa que el archivo exista y no este abierto en otro" + CRLF + ;
			"programa.", "ZCFDIIMP")
		Return
	EndIf

	cSrv := "\system\" + cNom

	cTxt := MemoRead(cSrv)
	If Empty(cTxt)
		MsgStop("El archivo se subio pero salio vacio al leerlo:" + CRLF + ;
			cSrv, "ZCFDIIMP")
		Return
	EndIf

	cMsg := "=== " + cNom + " ===" + CRLF + CRLF
	cMsg += "Subido al servidor: " + cSrv + CRLF
	cMsg += "Tamano: " + cValToChar(Len(cTxt)) + " bytes" + CRLF + CRLF

	If !("TIMBREFISCALDIGITAL" $ Upper(cTxt))
		cMsg += "[!] NO TRAE TIMBRE FISCAL." + CRLF + CRLF
		cMsg += "    Un XML sin timbre no es un CFDI valido ante el SAT." + CRLF
		cMsg += "    No entra al visor." + CRLF
		Return ImpMues("Un archivo mio", cMsg)
	EndIf

	cUuid := Upper(ImpStr(cTxt, "UUID"))
	If Empty(cUuid)
		cMsg += "[!] Trae timbre pero no se pudo leer el UUID." + CRLF
		Return ImpMues("Un archivo mio", cMsg)
	EndIf

	cMsg += "Folio fiscal: " + cUuid + CRLF + CRLF

	If ImpHayUu(cUuid)
		cMsg += "Este comprobante YA ESTABA cargado. No se duplica." + CRLF + CRLF
		cMsg += "Si quieres volver a cargarlo, hay que vaciar las tablas" + CRLF
		cMsg += "primero (Importar todo, contestando SI a vaciar)." + CRLF
		Return ImpMues("Un archivo mio", cMsg)
	EndIf

	If ImpUno(cTxt, cNom, "\system\", cUuid, @cFalla)
		cMsg += "CARGADO." + CRLF + CRLF

		// Si el visor esta abierto, que se entere solo.
		If U_ZCFDIREF()
			cMsg += "Ya aparece en la lista." + CRLF + CRLF
		Else
			cMsg += "Abre Ver CFDI para verlo." + CRLF + CRLF
		EndIf

		cMsg += "Para revisar que tan bien se leyo, entra a su Detalle:" + CRLF
		cMsg += "ahi salen los conceptos y los impuestos tal como" + CRLF
		cMsg += "quedaron guardados." + CRLF
	Else
		cMsg += "[!] NO SE PUDO CARGAR." + CRLF + CRLF
		cMsg += "    " + cFalla + CRLF
	EndIf

Return ImpMues("Un archivo mio", cMsg)

// ---------------------------------------------------------------------
Static Function ImpMues(cTitulo, cTexto)
	Local oDlg  := NIL
	Local oMem  := NIL
	Local cMemo := cTexto

	DEFINE MSDIALOG oDlg TITLE cTitulo FROM 0, 0 TO 400, 700 PIXEL

	@ 5, 5 GET oMem VAR cMemo MEMO SIZE 340, 175 OF oDlg PIXEL
	oMem:bWhen := {|| .F. }

	@ 185, 295 BUTTON "Ok" SIZE 40, 12 OF oDlg PIXEL ACTION oDlg:End()

	ACTIVATE MSDIALOG oDlg CENTERED

Return

// ---------------------------------------------------------------------
// Carga un comprobante completo. Devuelve .T. si quedo.
// ---------------------------------------------------------------------
Static Function ImpUno(cTxt, cNom, cRuta, cUuid, cFalla)
	Local oXml  := NIL
	Local oCom  := NIL
	Local cErr  := ""
	Local cWrn  := ""
	Local lOk   := .T.
	Local nSeqG := 0

	oXml := XmlParser(cTxt, "_", @cErr, @cWrn)

	If oXml == NIL .Or. !Empty(cErr)
		cFalla := "No se pudo parsear " + cNom + ": " + SubStr(cErr, 1, 120)
		Return .F.
	EndIf

	oCom := ImpNodo(oXml, "_CFDI_COMPROBANTE")
	If oCom == NIL
		oCom := oXml
	EndIf

	lOk := ImpZCF(oCom, cTxt, cNom, cRuta, cUuid)

	If lOk
		ImpZCC(oCom, cUuid)

		// ImpZCI devuelve la ultima secuencia que uso a nivel comprobante,
		// y los impuestos locales siguen contando desde ahi. No es un
		// detalle menor: la llave de ZCI es FILIAL+UUID+ITEM+SEQ, asi que
		// si los locales reiniciaran en 001 chocarian contra el traslado
		// federal y Oracle contestaria ORA-00001.
		nSeqG := ImpZCI(oCom, cUuid)
		ImpImpLoc(oCom, cUuid, nSeqG)

		ImpZCP(oCom, cUuid)

		// Comercio exterior. ImpZCE no hace nada si el comprobante no
		// trae el complemento, que son 57 de 66.
		ImpZCE(oCom, cUuid)
		ImpZCA(oCom, cUuid)
		ImpZCL(oCom, cUuid)
		ImpZCT(oCom, cUuid)
	EndIf

Return lOk

// ---------------------------------------------------------------------
// ZCF: la cabecera
// ---------------------------------------------------------------------
Static Function ImpZCF(oCom, cTxt, cNom, cRuta, cUuid)
	Local oEmi := ImpNodo(oCom, "_CFDI_EMISOR")
	Local oRec := ImpNodo(oCom, "_CFDI_RECEPTOR")
	Local cFec := ImpAtr(oCom, "_FECHA")
	Local cFTi := ImpStr(cTxt, "FechaTimbrado")
	Local oTot := NIL

	RecLock("ZCF", .T.)

	ZCF->ZCF_FILIAL := xFilial("ZCF")
	ZCF->ZCF_UUID   := cUuid
	ZCF->ZCF_VERSIO := ImpAtr(oCom, "_VERSION")
	ZCF->ZCF_TIPCOM := ImpAtr(oCom, "_TIPODECOMPROBANTE")
	ZCF->ZCF_SERIE  := ImpAtr(oCom, "_SERIE")
	ZCF->ZCF_FOLIO  := ImpAtr(oCom, "_FOLIO")
	ImpPonF("ZCF", "ZCF_FECHA", cFec)
	ZCF->ZCF_HORA   := SubStr(cFec, 12, 8)
	ZCF->ZCF_FORPAG := ImpAtr(oCom, "_FORMAPAGO")
	ZCF->ZCF_METPAG := ImpAtr(oCom, "_METODOPAGO")
	ZCF->ZCF_CONDPA := ImpAtr(oCom, "_CONDICIONESDEPAGO")
	ZCF->ZCF_MONEDA := ImpAtr(oCom, "_MONEDA")
	ZCF->ZCF_TIPCAM := ImpNum(ImpAtr(oCom, "_TIPOCAMBIO"))
	ZCF->ZCF_SUBTOT := ImpNum(ImpAtr(oCom, "_SUBTOTAL"))
	ZCF->ZCF_DESCTO := ImpNum(ImpAtr(oCom, "_DESCUENTO"))
	ZCF->ZCF_TOTAL  := ImpNum(ImpAtr(oCom, "_TOTAL"))
	ZCF->ZCF_LUGEXP := ImpAtr(oCom, "_LUGAREXPEDICION")
	ZCF->ZCF_EXPORT := ImpAtr(oCom, "_EXPORTACION")
	ZCF->ZCF_NOCERT := ImpAtr(oCom, "_NOCERTIFICADO")

	ZCF->ZCF_EMIRFC := ImpAtr(oEmi, "_RFC")
	ZCF->ZCF_EMINOM := ImpAtr(oEmi, "_NOMBRE")
	ZCF->ZCF_EMIREG := ImpAtr(oEmi, "_REGIMENFISCAL")

	ZCF->ZCF_RECRFC := ImpAtr(oRec, "_RFC")
	ZCF->ZCF_RECNOM := ImpAtr(oRec, "_NOMBRE")
	ZCF->ZCF_RECDOM := ImpAtr(oRec, "_DOMICILIOFISCALRECEPTOR")
	ZCF->ZCF_RECREG := ImpAtr(oRec, "_REGIMENFISCALRECEPTOR")

	// Receptor extranjero. Vienen juntos y solo cuando el receptor no es
	// mexicano: NumRegIdTrib es su identificacion fiscal en su pais y
	// ResidenciaFiscal el codigo del pais. En el censo salieron en 13 y
	// 12 de 133 -- son los comprobantes de exportacion.
	//
	// ImpPonC escribe solo si el campo existe en la tabla, asi que esto
	// no truena en un ambiente donde todavia no se corrio el alta de
	// columnas del diccionario.
	ImpPonC("ZCF", "ZCF_RECNRT", ImpAtr(oRec, "_NUMREGIDTRIB"))
	ImpPonC("ZCF", "ZCF_RECRES", ImpAtr(oRec, "_RESIDENCIAFISCAL"))
	ZCF->ZCF_USOCFD := ImpAtr(oRec, "_USOCFDI")

	// el timbre se lee por texto: esta dentro del complemento y su
	// estructura varia menos que su ruta de nodos
	ImpPonF("ZCF", "ZCF_FECTIM", cFTi)
	ZCF->ZCF_HORTIM := SubStr(cFTi, 12, 8)
	ZCF->ZCF_CERSAT := ImpStr(cTxt, "NoCertificadoSAT")
	ZCF->ZCF_RFCPAC := ImpStr(cTxt, "RfcProvCertif")

	// 'C' sale de que el archivo este en ANULADAS. El '?' NO significa
	// vigente: significa que todavia no se le ha preguntado al SAT.
	// Que un comprobante no este en ANULADAS no prueba que siga vivo.
	ZCF->ZCF_ESTSAT := IIf(ImpEsAnu(cRuta), "C", "?")
	ZCF->ZCF_VALIDE := "?"    // pendiente de validar contra catalogos
	ZCF->ZCF_ORIGEN := U_ZCFORIG(ZCF->ZCF_EMIRFC)
	ZCF->ZCF_ESPECI := ImpEspe(cNom)
	ZCF->ZCF_ARCHIV := cNom
	ZCF->ZCF_RUTA   := cRuta
	ImpPonD("ZCF", "ZCF_FECIMP", Date())

	// Totales del complemento de pago. Van en ZCF y no en ZCP porque
	// son UNO por comprobante, no uno por documento relacionado: si se
	// guardaran en ZCP se repetirian en cada renglon y cualquier suma
	// saldria multiplicada. Solo se escriben cuando el nodo existe,
	// para no llenar de ceros los 129 comprobantes que no son de pago.
	oTot := ImpTotPg(oCom)
	If oTot != NIL
		ImpPonN("ZCF", "ZCF_TOTPAG", ImpNum(ImpAtr(oTot, "_MONTOTOTALPAGOS")))
		ImpPonN("ZCF", "ZCF_BASIVA", ImpNum(ImpAtr(oTot, "_TOTALTRASLADOSBASEIVA16")))
		ImpPonN("ZCF", "ZCF_IVA16",  ImpNum(ImpAtr(oTot, "_TOTALTRASLADOSIMPUESTOIVA16")))
	EndIf

	ZCF->(MsUnlock())

Return .T.

// ---------------------------------------------------------------------
// ZCC: los conceptos
// ---------------------------------------------------------------------
Static Function ImpZCC(oCom, cUuid)
	Local oCps := ImpNodo(oCom, "_CFDI_CONCEPTOS")
	Local aCon := {}
	Local nI   := 0
	Local oC   := NIL

	If oCps == NIL
		Return
	EndIf

	aCon := ImpArr(ImpNodo(oCps, "_CFDI_CONCEPTO"))

	For nI := 1 To Len(aCon)
		oC := aCon[nI]

		RecLock("ZCC", .T.)
		ZCC->ZCC_FILIAL := xFilial("ZCC")
		ZCC->ZCC_UUID   := cUuid
		ZCC->ZCC_ITEM   := StrZero(nI, 4)
		ZCC->ZCC_CLAVE  := ImpAtr(oC, "_CLAVEPRODSERV")
		ZCC->ZCC_NOIDEN := ImpAtr(oC, "_NOIDENTIFICACION")
		ZCC->ZCC_CANT   := ImpNum(ImpAtr(oC, "_CANTIDAD"))
		ZCC->ZCC_CLAUNI := ImpAtr(oC, "_CLAVEUNIDAD")
		ZCC->ZCC_UNIDAD := ImpAtr(oC, "_UNIDAD")
		ZCC->ZCC_DESCRI := ImpAtr(oC, "_DESCRIPCION")
		ZCC->ZCC_VALUNI := ImpNum(ImpAtr(oC, "_VALORUNITARIO"))
		ZCC->ZCC_IMPORT := ImpNum(ImpAtr(oC, "_IMPORTE"))
		ZCC->ZCC_DESCTO := ImpNum(ImpAtr(oC, "_DESCUENTO"))
		ZCC->ZCC_OBJIMP := ImpAtr(oC, "_OBJETOIMP")
		ZCC->(MsUnlock())
	Next nI

Return

// ---------------------------------------------------------------------
// ZCI: los impuestos, en sus dos niveles
// ---------------------------------------------------------------------
Static Function ImpZCI(oCom, cUuid)
	Local oCps := ImpNodo(oCom, "_CFDI_CONCEPTOS")
	Local aCon := {}
	Local nI   := 0
	Local nSeq := 0

	// nivel concepto
	If oCps != NIL
		aCon := ImpArr(ImpNodo(oCps, "_CFDI_CONCEPTO"))
		For nI := 1 To Len(aCon)
			nSeq := 0
			ImpImp(ImpNodo(aCon[nI], "_CFDI_IMPUESTOS"), cUuid, ;
				StrZero(nI, 4), "C", @nSeq)
		Next nI
	EndIf

	// nivel comprobante
	nSeq := 0
	ImpImp(ImpNodo(oCom, "_CFDI_IMPUESTOS"), cUuid, "0000", "G", @nSeq)

// Se devuelve para que los impuestos locales continuen la numeracion.
Return nSeq

// ---------------------------------------------------------------------
// Graba traslados y retenciones de un nodo de impuestos
// ---------------------------------------------------------------------
Static Function ImpImp(oImp, cUuid, cItem, cNivel, nSeq)
	Local aTra := {}
	Local aRet := {}
	Local nI   := 0

	If oImp == NIL
		Return
	EndIf

	aTra := ImpArr(ImpNodo(ImpNodo(oImp, "_CFDI_TRASLADOS"), "_CFDI_TRASLADO"))
	aRet := ImpArr(ImpNodo(ImpNodo(oImp, "_CFDI_RETENCIONES"), "_CFDI_RETENCION"))

	For nI := 1 To Len(aTra)
		nSeq++
		ImpGrbI(aTra[nI], cUuid, cItem, cNivel, "T", nSeq)
	Next nI

	For nI := 1 To Len(aRet)
		nSeq++
		ImpGrbI(aRet[nI], cUuid, cItem, cNivel, "R", nSeq)
	Next nI

Return

// ---------------------------------------------------------------------
Static Function ImpGrbI(oNod, cUuid, cItem, cNivel, cTipo, nSeq, cSuf)

	// El complemento de pago usa los MISMOS cinco datos pero con el
	// nombre del atributo terminado en DR o en P (BaseDR, BaseP...).
	// Por eso el sufijo: el renglon que se guarda es identico, lo unico
	// que cambia es como se llama el atributo en el XML.
	Default cSuf := ""

	RecLock("ZCI", .T.)
	ZCI->ZCI_FILIAL := xFilial("ZCI")
	ZCI->ZCI_UUID   := cUuid
	ZCI->ZCI_ITEM   := cItem
	ZCI->ZCI_SEQ    := StrZero(nSeq, 3)
	ZCI->ZCI_NIVEL  := cNivel
	ZCI->ZCI_TIPO   := cTipo
	ZCI->ZCI_IMPUES := ImpAtr(oNod, "_IMPUESTO"   + cSuf)
	ZCI->ZCI_BASE   := ImpNum(ImpAtr(oNod, "_BASE" + cSuf))
	ZCI->ZCI_TIPFAC := ImpAtr(oNod, "_TIPOFACTOR" + cSuf)
	ZCI->ZCI_TASA   := ImpNum(ImpAtr(oNod, "_TASAOCUOTA" + cSuf))
	ZCI->ZCI_IMPORT := ImpNum(ImpAtr(oNod, "_IMPORTE" + cSuf))
	ZCI->(MsUnlock())

Return

// ---------------------------------------------------------------------
// El nodo Totales del complemento de pago, o NIL si el comprobante no
// es de pago. Cuelga de pago20:Pagos, al mismo nivel que los Pago, no
// de cada Pago -- por eso hay uno solo por comprobante.
// ---------------------------------------------------------------------
Static Function ImpTotPg(oCom)
	Local oCpl := ImpNodo(oCom, "_CFDI_COMPLEMENTO")
	Local oPgs := NIL

	If ImpAtr(oCom, "_TIPODECOMPROBANTE") != "P" .Or. oCpl == NIL
		Return NIL
	EndIf

	oPgs := ImpNodo(oCpl, "_PAGO20_PAGOS")
	If oPgs == NIL
		Return NIL
	EndIf

Return ImpNodo(oPgs, "_PAGO20_TOTALES")

// =====================================================================
// ZCE Y ZCM: COMERCIO EXTERIOR
//
// El complemento cce20 cuelga de cfdi:Complemento y trae tres cosas de
// grano distinto: los atributos del nodo ComercioExterior (uno por
// comprobante), los dos domicilios -- emisor y receptor -- que tambien
// son uno por comprobante, y las Mercancias, que son una a muchas.
//
// Los dos primeros grupos viven juntos en ZCE porque separar dos nodos
// que son 1 a 1 con el comprobante no gana nada y obliga a un join
// para contestar cualquier pregunta. Las mercancias van en ZCM.
// =====================================================================
Static Function ImpZCE(oCom, cUuid)
	Local oCpl := ImpNodo(oCom, "_CFDI_COMPLEMENTO")
	Local oCce := NIL
	Local oEmi := NIL
	Local oRec := NIL
	Local oDom := NIL

	If oCpl == NIL
		Return
	EndIf

	oCce := ImpNodo(oCpl, "_CCE20_COMERCIOEXTERIOR")
	If oCce == NIL
		Return
	EndIf

	oEmi := ImpNodo(oCce, "_CCE20_EMISOR")
	oRec := ImpNodo(oCce, "_CCE20_RECEPTOR")

	RecLock("ZCE", .T.)
	ZCE->ZCE_FILIAL := xFilial("ZCE")
	ZCE->ZCE_UUID   := cUuid
	ZCE->ZCE_VERSIO := ImpAtr(oCce, "_VERSION")
	ZCE->ZCE_CVEPED := ImpAtr(oCce, "_CLAVEDEPEDIMENTO")
	ZCE->ZCE_CERORI := ImpAtr(oCce, "_CERTIFICADOORIGEN")
	ZCE->ZCE_NUMEXP := ImpAtr(oCce, "_NUMEROEXPORTADORCONFIABLE")
	ZCE->ZCE_INCOTE := ImpAtr(oCce, "_INCOTERM")
	ZCE->ZCE_MOTTRA := ImpAtr(oCce, "_MOTIVOTRASLADO")
	ZCE->ZCE_TIPCAM := ImpNum(ImpAtr(oCce, "_TIPOCAMBIOUSD"))
	ZCE->ZCE_TOTUSD := ImpNum(ImpAtr(oCce, "_TOTALUSD"))

	If oEmi != NIL
		oDom := ImpNodo(oEmi, "_CCE20_DOMICILIO")
		If oDom != NIL
			ZCE->ZCE_EMICAL := ImpAtr(oDom, "_CALLE")
			ZCE->ZCE_EMICP  := ImpAtr(oDom, "_CODIGOPOSTAL")
			ZCE->ZCE_EMICOL := ImpAtr(oDom, "_COLONIA")
			ZCE->ZCE_EMIMUN := ImpAtr(oDom, "_MUNICIPIO")
			ZCE->ZCE_EMIEST := ImpAtr(oDom, "_ESTADO")
			ZCE->ZCE_EMIPAI := ImpAtr(oDom, "_PAIS")
		EndIf
	EndIf

	If oRec != NIL
		ZCE->ZCE_RECNRT := ImpAtr(oRec, "_NUMREGIDTRIB")
		oDom := ImpNodo(oRec, "_CCE20_DOMICILIO")
		If oDom != NIL
			ZCE->ZCE_RECCAL := ImpAtr(oDom, "_CALLE")
			ZCE->ZCE_RECCP  := ImpAtr(oDom, "_CODIGOPOSTAL")
			ZCE->ZCE_RECCOL := ImpAtr(oDom, "_COLONIA")
			ZCE->ZCE_RECMUN := ImpAtr(oDom, "_MUNICIPIO")
			ZCE->ZCE_RECEST := ImpAtr(oDom, "_ESTADO")
			ZCE->ZCE_RECPAI := ImpAtr(oDom, "_PAIS")
		EndIf
	EndIf

	ZCE->(MsUnlock())

	ImpZCM(oCce, cUuid)

Return

// ---------------------------------------------------------------------
Static Function ImpZCM(oCce, cUuid)
	Local oMcs := ImpNodo(oCce, "_CCE20_MERCANCIAS")
	Local aMer := {}
	Local nI   := 0
	Local oM   := NIL

	If oMcs == NIL
		Return
	EndIf

	aMer := ImpArr(ImpNodo(oMcs, "_CCE20_MERCANCIA"))

	For nI := 1 To Len(aMer)
		oM := aMer[nI]

		RecLock("ZCM", .T.)
		ZCM->ZCM_FILIAL := xFilial("ZCM")
		ZCM->ZCM_UUID   := cUuid
		ZCM->ZCM_ITEM   := StrZero(nI, 4)
		ZCM->ZCM_NOIDEN := ImpAtr(oM, "_NOIDENTIFICACION")
		ZCM->ZCM_FRACC  := ImpAtr(oM, "_FRACCIONARANCELARIA")
		ZCM->ZCM_CANADU := ImpNum(ImpAtr(oM, "_CANTIDADADUANA"))
		ZCM->ZCM_UNIADU := ImpAtr(oM, "_UNIDADADUANA")
		ZCM->ZCM_VALUNI := ImpNum(ImpAtr(oM, "_VALORUNITARIOADUANA"))
		ZCM->ZCM_VALDOL := ImpNum(ImpAtr(oM, "_VALORDOLARES"))
		ZCM->(MsUnlock())
	Next nI

Return

// =====================================================================
// CARTA PORTE
//
// El complemento mas grande del SAT, y el que mas se presta a inventar
// una tabla por nodo. Son cuatro granos y nada mas:
//
//   ZCT  el viaje              uno por comprobante
//   ZCU  las paradas           uno a muchos
//   ZCB  lo que se transporta  uno a muchos
//   ZCG  quien lo maneja       uno a muchos
//
// Autotransporte, IdentificacionVehicular y Seguros son tres nodos
// anidados en el XML pero los tres son 1 a 1 con la carta porte, asi
// que viven aplanados en ZCT. Lo mismo el Domicilio dentro de ZCU.
// =====================================================================
Static Function ImpZCT(oCom, cUuid)
	Local oCpl := ImpNodo(oCom, "_CFDI_COMPLEMENTO")
	Local oCP  := NIL
	Local oMcs := NIL
	Local oAut := NIL
	Local oIdV := NIL
	Local oSeg := NIL

	If oCpl == NIL
		Return
	EndIf

	oCP := ImpNodo(oCpl, "_CARTAPORTE31_CARTAPORTE")
	If oCP == NIL
		Return
	EndIf

	oMcs := ImpNodo(oCP, "_CARTAPORTE31_MERCANCIAS")

	If oMcs != NIL
		oAut := ImpNodo(oMcs, "_CARTAPORTE31_AUTOTRANSPORTE")
	EndIf
	If oAut != NIL
		oIdV := ImpNodo(oAut, "_CARTAPORTE31_IDENTIFICACIONVEHICULAR")
		oSeg := ImpNodo(oAut, "_CARTAPORTE31_SEGUROS")
	EndIf

	RecLock("ZCT", .T.)
	ZCT->ZCT_FILIAL := xFilial("ZCT")
	ZCT->ZCT_UUID   := cUuid
	ZCT->ZCT_VERSIO := ImpAtr(oCP, "_VERSION")
	ZCT->ZCT_IDCCP  := ImpAtr(oCP, "_IDCCP")
	ZCT->ZCT_TRAINT := ImpAtr(oCP, "_TRANSPINTERNAC")
	ZCT->ZCT_TOTDIS := ImpNum(ImpAtr(oCP, "_TOTALDISTREC"))

	If oMcs != NIL
		ZCT->ZCT_NUMMER := ImpNum(ImpAtr(oMcs, "_NUMTOTALMERCANCIAS"))
		ZCT->ZCT_PESBRU := ImpNum(ImpAtr(oMcs, "_PESOBRUTOTOTAL"))
		ZCT->ZCT_UNIPES := ImpAtr(oMcs, "_UNIDADPESO")
	EndIf

	If oAut != NIL
		ZCT->ZCT_PERSCT := ImpAtr(oAut, "_PERMSCT")
		ZCT->ZCT_NUMPER := ImpAtr(oAut, "_NUMPERMISOSCT")
	EndIf

	If oIdV != NIL
		ZCT->ZCT_PLACA  := ImpAtr(oIdV, "_PLACAVM")
		ZCT->ZCT_ANIOVM := ImpNum(ImpAtr(oIdV, "_ANIOMODELOVM"))
		ZCT->ZCT_CONFVE := ImpAtr(oIdV, "_CONFIGVEHICULAR")
	EndIf

	If oSeg != NIL
		ZCT->ZCT_ASEGUR := ImpAtr(oSeg, "_ASEGURARESPCIVIL")
		ZCT->ZCT_POLIZA := ImpAtr(oSeg, "_POLIZARESPCIVIL")
	EndIf

	ZCT->(MsUnlock())

	ImpZCU(oCP, cUuid)
	ImpZCB(oMcs, cUuid)
	ImpZCG(oCP, cUuid)

Return

// ---------------------------------------------------------------------
Static Function ImpZCU(oCP, cUuid)
	Local oUbs := ImpNodo(oCP, "_CARTAPORTE31_UBICACIONES")
	Local aUbi := {}
	Local oU   := NIL
	Local oDom := NIL
	Local nI   := 0
	Local cFH  := ""

	If oUbs == NIL
		Return
	EndIf

	aUbi := ImpArr(ImpNodo(oUbs, "_CARTAPORTE31_UBICACION"))

	For nI := 1 To Len(aUbi)
		oU  := aUbi[nI]
		cFH := ImpAtr(oU, "_FECHAHORASALIDALLEGADA")

		RecLock("ZCU", .T.)
		ZCU->ZCU_FILIAL := xFilial("ZCU")
		ZCU->ZCU_UUID   := cUuid
		ZCU->ZCU_ITEM   := StrZero(nI, 4)
		ZCU->ZCU_TIPO   := ImpAtr(oU, "_TIPOUBICACION")
		ZCU->ZCU_RFC    := ImpAtr(oU, "_RFCREMITENTEDESTINATARIO")
		ZCU->ZCU_NOMBRE := ImpAtr(oU, "_NOMBREREMITENTEDESTINATARIO")
		ImpPonF("ZCU", "ZCU_FECHA", cFH)
		ZCU->ZCU_HORA   := SubStr(cFH, 12, 8)
		ZCU->ZCU_DISTAN := ImpNum(ImpAtr(oU, "_DISTANCIARECORRIDA"))

		oDom := ImpNodo(oU, "_CARTAPORTE31_DOMICILIO")
		If oDom != NIL
			ZCU->ZCU_CALLE  := ImpAtr(oDom, "_CALLE")
			ZCU->ZCU_NUMEXT := ImpAtr(oDom, "_NUMEROEXTERIOR")
			ZCU->ZCU_CP     := ImpAtr(oDom, "_CODIGOPOSTAL")
			ZCU->ZCU_LOCALI := ImpAtr(oDom, "_LOCALIDAD")
			ZCU->ZCU_MUNICI := ImpAtr(oDom, "_MUNICIPIO")
			ZCU->ZCU_ESTADO := ImpAtr(oDom, "_ESTADO")
			ZCU->ZCU_PAIS   := ImpAtr(oDom, "_PAIS")
		EndIf

		ZCU->(MsUnlock())
	Next nI

Return

// ---------------------------------------------------------------------
Static Function ImpZCB(oMcs, cUuid)
	Local aMer := {}
	Local oM   := NIL
	Local nI   := 0

	If oMcs == NIL
		Return
	EndIf

	aMer := ImpArr(ImpNodo(oMcs, "_CARTAPORTE31_MERCANCIA"))

	For nI := 1 To Len(aMer)
		oM := aMer[nI]

		RecLock("ZCB", .T.)
		ZCB->ZCB_FILIAL := xFilial("ZCB")
		ZCB->ZCB_UUID   := cUuid
		ZCB->ZCB_ITEM   := StrZero(nI, 4)
		ZCB->ZCB_BIENES := ImpAtr(oM, "_BIENESTRANSP")
		ZCB->ZCB_DESCRI := ImpAtr(oM, "_DESCRIPCION")
		ZCB->ZCB_CANT   := ImpNum(ImpAtr(oM, "_CANTIDAD"))
		ZCB->ZCB_CLAUNI := ImpAtr(oM, "_CLAVEUNIDAD")
		ZCB->ZCB_PESKG  := ImpNum(ImpAtr(oM, "_PESOENKG"))
		ZCB->ZCB_VALOR  := ImpNum(ImpAtr(oM, "_VALORMERCANCIA"))
		ZCB->ZCB_MONEDA := ImpAtr(oM, "_MONEDA")
		ZCB->(MsUnlock())
	Next nI

Return

// ---------------------------------------------------------------------
Static Function ImpZCG(oCP, cUuid)
	Local oFig := ImpNodo(oCP, "_CARTAPORTE31_FIGURATRANSPORTE")
	Local aTip := {}
	Local oT   := NIL
	Local nI   := 0

	If oFig == NIL
		Return
	EndIf

	aTip := ImpArr(ImpNodo(oFig, "_CARTAPORTE31_TIPOSFIGURA"))

	For nI := 1 To Len(aTip)
		oT := aTip[nI]

		RecLock("ZCG", .T.)
		ZCG->ZCG_FILIAL := xFilial("ZCG")
		ZCG->ZCG_UUID   := cUuid
		ZCG->ZCG_ITEM   := StrZero(nI, 4)
		ZCG->ZCG_TIPFIG := ImpAtr(oT, "_TIPOFIGURA")
		ZCG->ZCG_RFC    := ImpAtr(oT, "_RFCFIGURA")
		ZCG->ZCG_NOMBRE := ImpAtr(oT, "_NOMBREFIGURA")
		ZCG->ZCG_LICENC := ImpAtr(oT, "_NUMLICENCIA")
		ZCG->(MsUnlock())
	Next nI

Return

// ---------------------------------------------------------------------
// ZCL: LOS CFDI RELACIONADOS
//
// Dos niveles, y los dos pueden repetirse: CfdiRelacionados aparece una
// vez por TipoRelacion, y cada uno cuelga varios CfdiRelacionado. Por
// eso el tipo se guarda en CADA renglon -- un comprobante puede
// sustituir a uno ('04') y ser nota de credito de otro ('01') al mismo
// tiempo, y una cabecera con un solo tipo mentiria.
//
// El item es un contador CORRIDO sobre los dos niveles, no uno por
// grupo: la llave es FILIAL+UUID+ITEM y si cada grupo reiniciara en
// 0001 el segundo chocaria contra el primero. Es el mismo golpe que ya
// dio ZCI con los niveles del complemento de pago.
// ---------------------------------------------------------------------
Static Function ImpZCL(oCom, cUuid)
	Local aGru := {}
	Local aRel := {}
	Local nI   := 0
	Local nJ   := 0
	Local nIt  := 0
	Local cTip := ""

	aGru := ImpArr(ImpNodo(oCom, "_CFDI_CFDIRELACIONADOS"))

	For nI := 1 To Len(aGru)
		cTip := ImpAtr(aGru[nI], "_TIPORELACION")
		aRel := ImpArr(ImpNodo(aGru[nI], "_CFDI_CFDIRELACIONADO"))

		For nJ := 1 To Len(aRel)
			nIt++

			RecLock("ZCL", .T.)
			ZCL->ZCL_FILIAL := xFilial("ZCL")
			ZCL->ZCL_UUID   := cUuid
			ZCL->ZCL_ITEM   := StrZero(nIt, 4)
			ZCL->ZCL_TIPREL := cTip
			ZCL->ZCL_UUIDRE := Upper(ImpAtr(aRel[nJ], "_UUID"))
			ZCL->(MsUnlock())
		Next nJ
	Next nI

Return

// ---------------------------------------------------------------------
// ZCA: EL PEDIMENTO DE CADA CONCEPTO
//
// InformacionAduanera NO es parte de cce20: cuelga directo del concepto
// de cfdi. Se lee aparte por eso, y se recorren los conceptos de nuevo
// en vez de meterlo en ImpZCC para no mezclar dos tablas en una
// funcion que ya hace una cosa bien.
//
// Puede venir mas de uno por concepto -- de ahi ZCA_SEQ.
// ---------------------------------------------------------------------
Static Function ImpZCA(oCom, cUuid)
	Local oCps := ImpNodo(oCom, "_CFDI_CONCEPTOS")
	Local aCon := {}
	Local aAdu := {}
	Local nI   := 0
	Local nJ   := 0

	If oCps == NIL
		Return
	EndIf

	aCon := ImpArr(ImpNodo(oCps, "_CFDI_CONCEPTO"))

	For nI := 1 To Len(aCon)
		aAdu := ImpArr(ImpNodo(aCon[nI], "_CFDI_INFORMACIONADUANERA"))

		For nJ := 1 To Len(aAdu)
			RecLock("ZCA", .T.)
			ZCA->ZCA_FILIAL := xFilial("ZCA")
			ZCA->ZCA_UUID   := cUuid
			ZCA->ZCA_ITEM   := StrZero(nI, 4)
			ZCA->ZCA_SEQ    := StrZero(nJ, 3)
			ZCA->ZCA_PEDIME := ImpAtr(aAdu[nJ], "_NUMEROPEDIMENTO")
			ZCA->(MsUnlock())
		Next nJ
	Next nI

Return

// ---------------------------------------------------------------------
// Suma de los traslados de un documento relacionado. Se SUMAN en vez de
// tomar el primero porque un documento puede traer mas de uno, y
// quedarse con uno solo es la clase de error que nadie nota hasta que
// las sumas no cuadran por centavos.
// ---------------------------------------------------------------------
Static Function ImpSumDR(oD)
	Local oImp := ImpNodo(oD, "_PAGO20_IMPUESTOSDR")
	Local aTra := {}
	Local nI   := 0
	Local nRet := 0

	If oImp == NIL
		Return 0
	EndIf

	aTra := ImpArr(ImpNodo(ImpNodo(oImp, "_PAGO20_TRASLADOSDR"), ;
		"_PAGO20_TRASLADODR"))

	For nI := 1 To Len(aTra)
		nRet += ImpNum(ImpAtr(aTra[nI], "_IMPORTEDR"))
	Next nI

Return nRet

// ---------------------------------------------------------------------
// LOS IMPUESTOS DEL COMPLEMENTO DE PAGO
//
// Misma idea que ImpImp, pero los contenedores del complemento de pago
// se llaman distinto: TrasladosDR/TrasladoDR colgando de ImpuestosDR, y
// TrasladosP/TrasladoP colgando de ImpuestosP. El sufijo sirve para las
// dos cosas -- el nombre del nodo y el del atributo -- porque el SAT
// los nombro igual.
//
// Esto es lo que contesta "cuanto IVA trae un PPD": hasta ahora el
// visor guardaba el monto del pago pero no su desglose de impuestos, y
// sin el desglose no se puede cuadrar el IVA de los complementos
// contra nada.
// ---------------------------------------------------------------------
Static Function ImpImpPg(oImp, cUuid, cItem, cNivel, nSeq, cSuf)
	Local aTra := {}
	Local aRet := {}
	Local nI   := 0

	If oImp == NIL
		Return nSeq
	EndIf

	aTra := ImpArr(ImpNodo(ImpNodo(oImp, "_PAGO20_TRASLADOS" + cSuf), ;
		"_PAGO20_TRASLADO" + cSuf))
	aRet := ImpArr(ImpNodo(ImpNodo(oImp, "_PAGO20_RETENCIONES" + cSuf), ;
		"_PAGO20_RETENCION" + cSuf))

	For nI := 1 To Len(aTra)
		nSeq++
		ImpGrbI(aTra[nI], cUuid, cItem, cNivel, "T", nSeq, cSuf)
	Next nI

	For nI := 1 To Len(aRet)
		nSeq++
		ImpGrbI(aRet[nI], cUuid, cItem, cNivel, "R", nSeq, cSuf)
	Next nI

Return nSeq

// ---------------------------------------------------------------------
// ZCP: complemento de pagos. Solo aplica a los tipo P.
//
// Un REP puede traer varios pagos, y cada pago varios documentos
// relacionados. Se guarda un renglon por documento relacionado, que es
// el nivel al que sirve para conciliar contra las facturas.
// ---------------------------------------------------------------------
Static Function ImpZCP(oCom, cUuid)
	Local oCpl := ImpNodo(oCom, "_CFDI_COMPLEMENTO")
	Local oPgs := NIL
	Local aPag := {}
	Local aDoc := {}
	Local nI   := 0
	Local nJ   := 0
	Local nIt  := 0
	Local oP   := NIL
	Local oD   := NIL
	Local nSeqD:= 0
	Local nSeqP:= 0

	If ImpAtr(oCom, "_TIPODECOMPROBANTE") != "P" .Or. oCpl == NIL
		Return
	EndIf

	oPgs := ImpNodo(oCpl, "_PAGO20_PAGOS")
	If oPgs == NIL
		oPgs := ImpNodo(oCpl, "_PAGO10_PAGOS")
	EndIf
	If oPgs == NIL
		Return
	EndIf

	aPag := ImpArr(ImpNodo(oPgs, "_PAGO20_PAGO"))
	If Len(aPag) == 0
		aPag := ImpArr(ImpNodo(oPgs, "_PAGO10_PAGO"))
	EndIf

	For nI := 1 To Len(aPag)
		oP  := aPag[nI]
		aDoc := ImpArr(ImpNodo(oP, "_PAGO20_DOCTORELACIONADO"))
		If Len(aDoc) == 0
			aDoc := ImpArr(ImpNodo(oP, "_PAGO10_DOCTORELACIONADO"))
		EndIf

		For nJ := 1 To Len(aDoc)
			oD := aDoc[nJ]
			nIt++

			RecLock("ZCP", .T.)
			ZCP->ZCP_FILIAL := xFilial("ZCP")
			ZCP->ZCP_UUID   := cUuid
			ZCP->ZCP_ITEM   := StrZero(nIt, 4)
			ImpPonF("ZCP", "ZCP_FECPAG", ImpAtr(oP, "_FECHAPAGO"))
			ZCP->ZCP_FORPAG := ImpAtr(oP, "_FORMADEPAGOP")
			ZCP->ZCP_MONEDA := ImpAtr(oP, "_MONEDAP")
			ZCP->ZCP_TIPCAM := ImpNum(ImpAtr(oP, "_TIPOCAMBIOP"))
			ZCP->ZCP_MONTO  := ImpNum(ImpAtr(oP, "_MONTO"))
			ZCP->ZCP_UUIDRE := Upper(ImpAtr(oD, "_IDDOCUMENTO"))
			ZCP->ZCP_SERIE  := ImpAtr(oD, "_SERIE")
			ZCP->ZCP_FOLIO  := ImpAtr(oD, "_FOLIO")
			ZCP->ZCP_PARCIA := ImpAtr(oD, "_NUMPARCIALIDAD")
			ZCP->ZCP_SALANT := ImpNum(ImpAtr(oD, "_IMPSALDOANT"))
			ZCP->ZCP_SALPAG := ImpNum(ImpAtr(oD, "_IMPPAGADO"))
			ZCP->ZCP_SALINS := ImpNum(ImpAtr(oD, "_IMPSALDOINSOLUTO"))
			ZCP->ZCP_OBJIMP := ImpAtr(oD, "_OBJETOIMPDR")

			// Atributos que faltaban. NumOperacion cuelga del Pago;
			// MonedaDR y EquivalenciaDR del documento relacionado --
			// son los que permiten cuadrar un pago en una moneda
			// contra una factura en otra.
			ImpPonC("ZCP", "ZCP_NUMOPE", ImpAtr(oP, "_NUMOPERACION"))
			ImpPonC("ZCP", "ZCP_MONEDR", ImpAtr(oD, "_MONEDADR"))
			ImpPonN("ZCP", "ZCP_EQUIVA", ImpNum(ImpAtr(oD, "_EQUIVALENCIADR")))

			// El IVA del documento, sumado, en el propio renglon del
			// pago. El desglose completo queda en ZCI, pero tenerlo
			// aqui evita que cualquier consulta del complemento tenga
			// que cruzar dos tablas para contestar "cuanto de esto es
			// IVA", que es la pregunta que se hace siempre.
			ZCP->ZCP_IVAPAG := ImpSumDR(oD)

			ZCP->(MsUnlock())

			// Impuestos del documento relacionado -> ZCI nivel 'D'.
			//
			// El item lleva la letra del nivel adelante ("D001") y no
			// el numero pelon. El indice unico de ZCI es
			// FILIAL+UUID+ITEM+SEQ y NO incluye ZCI_NIVEL, asi que dos
			// niveles distintos con el mismo item y la misma secuencia
			// chocan: el documento relacionado 1 y el pago 1 del mismo
			// comprobante eran los dos 0001/001. Dandole a cada nivel
			// su propio espacio de items el choque no puede ocurrir, y
			// no hay que tocar el indice de una tabla que ya tiene
			// datos.
			nSeqD := 0
			ImpImpPg(ImpNodo(oD, "_PAGO20_IMPUESTOSDR"), cUuid, ;
				"D" + StrZero(nIt, 3), "D", @nSeqD, "DR")
		Next nJ

		// Impuestos del pago completo -> ZCI nivel 'P'. Cuelgan del
		// Pago, no del documento, asi que van una sola vez por pago.
		nSeqP := 0
		ImpImpPg(ImpNodo(oP, "_PAGO20_IMPUESTOSP"), cUuid, ;
			"P" + StrZero(nI, 3), "P", @nSeqP, "P")
	Next nI

Return

// ---------------------------------------------------------------------
// LA LLAVE DE ZCR SIRVE PARA DOS COSAS DISTINTAS
//
// ZCR concilia dos mundos: documentos de Protheus y archivos del
// servidor. ZCR_TABLA dice cual de los dos es cada renglon, y de eso
// depende como se leen los otros campos de la llave:
//
//   ZCR_TABLA = 'SF2' etc  -> es un documento: SERIE + DOC lo
//                             identifican, y el UUID puede venir vacio
//   ZCR_TABLA = 'XML'      -> es un archivo: no hay documento ni serie,
//                             y DOC lleva un consecutivo de la corrida.
//                             El nombre del archivo va en ZCR_OBS.
//
// El consecutivo no es decorativo: sin el, dos archivos sin timbre
// generan la misma llave (todo vacio) y el segundo choca contra el
// primero. Eso fue exactamente el ORA-00001 de la primera corrida.
//
// Estados: C conciliado, X solo XML, D solo documento,
//          S archivo sin timbre, E archivo con problema
// ---------------------------------------------------------------------
Static Function ImpZCR(cUuid, cTabla, cSerie, cDoc, cEstado, cObs)

	RecLock("ZCR", .T.)
	ZCR->ZCR_FILIAL := xFilial("ZCR")
	ZCR->ZCR_UUID   := cUuid
	ZCR->ZCR_TABLA  := cTabla
	ZCR->ZCR_SERIE  := cSerie
	ZCR->ZCR_DOC    := cDoc
	ZCR->ZCR_ESTADO := cEstado
	ImpPonD("ZCR", "ZCR_FECHA", Date())
	ZCR->ZCR_OBS    := SubStr(cObs, 1, 250)
	ZCR->(MsUnlock())

Return

// =====================================================================
// IMPUESTOS LOCALES
//
// Son los impuestos estatales o municipales -- el ISH hotelero, por
// ejemplo. Viven en su propio namespace y NO cuelgan del comprobante ni
// del concepto: van dentro del Complemento.
//
//   cfdi:Comprobante
//     cfdi:Complemento
//       implocal:ImpuestosLocales
//         implocal:TrasladosLocales    ImpLocTrasladado, TasadeTraslado, Importe
//         implocal:RetencionesLocales  ImpLocRetenido,   TasadeRetencion, Importe
//
// Ojo con los atributos: NO son los mismos que los de los impuestos
// federales. No hay Base ni TipoFactor, y el impuesto viene con nombre
// ("ISH"), no con clave numerica.
//
// COMO SE GUARDAN EN ZCI
//
// Se reusa la misma tabla. ZCI_NIVEL = "L" los marca como locales, y
// ZCI_TIPO conserva su significado de siempre: T traslado, R retencion.
// Se prefirio eso a inventar un valor de TIPO nuevo, que habria obligado
// a leer TIPO distinto segun la fila.
// =====================================================================
Static Function ImpImpLoc(oCom, cUuid, nSeq)
	Local oCpl := ImpNodo(oCom, "_CFDI_COMPLEMENTO")
	Local oLoc := NIL
	Local aTra := {}
	Local aRet := {}
	Local nI   := 0

	If oCpl == NIL
		Return
	EndIf

	// No hay certeza de como bautiza XmlParser un nodo con namespace
	// propio, asi que se prueban las dos formas posibles en vez de
	// apostarle a una. Si alguna vez se sabe cual es, se puede podar.
	oLoc := ImpNodoAlt(oCpl, {"_IMPLOCAL_IMPUESTOSLOCALES", ;
		"_IMPUESTOSLOCALES"})
	If oLoc == NIL
		Return
	EndIf

	aTra := ImpArr(ImpNodoAlt(oLoc, {"_IMPLOCAL_TRASLADOSLOCALES", ;
		"_TRASLADOSLOCALES"}))
	aRet := ImpArr(ImpNodoAlt(oLoc, {"_IMPLOCAL_RETENCIONESLOCALES", ;
		"_RETENCIONESLOCALES"}))

	For nI := 1 To Len(aTra)
		nSeq++
		ImpGrbIL(aTra[nI], cUuid, nSeq, "T", ;
			"_IMPLOCTRASLADADO", "_TASADETRASLADO")
	Next nI

	For nI := 1 To Len(aRet)
		nSeq++
		ImpGrbIL(aRet[nI], cUuid, nSeq, "R", ;
			"_IMPLOCRETENIDO", "_TASADERETENCION")
	Next nI

Return

// ---------------------------------------------------------------------
// Graba un impuesto local. Los nombres de atributo se reciben porque
// traslados y retenciones los llaman distinto.
// ---------------------------------------------------------------------
Static Function ImpGrbIL(oNod, cUuid, nSeq, cTipo, cAtrImp, cAtrTasa)

	RecLock("ZCI", .T.)
	ZCI->ZCI_FILIAL := xFilial("ZCI")
	ZCI->ZCI_UUID   := cUuid
	ZCI->ZCI_ITEM   := "0000"      // los locales son siempre de comprobante
	ZCI->ZCI_SEQ    := StrZero(nSeq, 3)
	ZCI->ZCI_NIVEL  := "L"
	ZCI->ZCI_TIPO   := cTipo
	ZCI->ZCI_IMPUES := ImpAtr(oNod, cAtrImp)
	ZCI->ZCI_BASE   := 0           // el implocal no trae base
	ZCI->ZCI_TIPFAC := ""          // ni tipo de factor
	ZCI->ZCI_TASA   := ImpNum(ImpAtr(oNod, cAtrTasa))
	ZCI->ZCI_IMPORT := ImpNum(ImpAtr(oNod, "_IMPORTE"))
	ZCI->(MsUnlock())

Return

// =====================================================================
// RECARGAR UN COMPROBANTE
//
// Vaciar el visor era todo o nada, y en pruebas uno quiere volver a leer
// UN xml despues de tocar el parser sin tirar los demas.
//
// Se puede porque ZCF guarda de donde salio cada comprobante
// (ZCF_RUTA + ZCF_ARCHIV): no hay que volver a subir nada.
//
// Se borra de las cuatro tablas y se vuelve a leer. ZCR no se toca: ahi
// vive la conciliacion, que es de otra corrida.
// =====================================================================
User Function ZCFDIREC()
	Local cUuid  := AllTrim(ZCF->ZCF_UUID)
	Local cRuta  := AllTrim(ZCF->ZCF_RUTA)
	Local cNom   := AllTrim(ZCF->ZCF_ARCHIV)
	Local cSerie := AllTrim(ZCF->ZCF_SERIE)
	Local cFolio := AllTrim(ZCF->ZCF_FOLIO)
	Local cArq   := ""
	Local cTxt   := ""
	Local cFalla := ""
	Local cMsg   := ""

	If !ImpAbre()
		Return
	EndIf

	If Empty(cUuid)
		MsgStop("No hay un comprobante seleccionado.", "ZCFDIIMP")
		Return
	EndIf

	If Empty(cNom)
		MsgStop("Este comprobante no guarda de que archivo salio," + CRLF + ;
			"asi que no hay de donde recargarlo.", "ZCFDIIMP")
		Return
	EndIf

	cArq := cRuta + cNom
	cTxt := MemoRead(cArq)

	// Se lee ANTES de borrar: si el archivo ya no esta, mejor no haber
	// tocado nada.
	If Empty(cTxt)
		MsgStop("No se pudo leer el archivo:" + CRLF + CRLF + ;
			cArq + CRLF + CRLF + ;
			"No se borro nada. Si el archivo ya no esta en el servidor," + CRLF + ;
			"subelo de nuevo con Importar.", "ZCFDIIMP")
		Return
	EndIf

	If !MsgYesNo("Recargar este comprobante?" + CRLF + CRLF + ;
		"   " + cSerie + " " + cFolio + CRLF + ;
		"   " + cUuid + CRLF + CRLF + ;
		"Se borra de ZCF, ZCC, ZCI y ZCP y se vuelve a leer desde" + CRLF + ;
		cArq + CRLF + CRLF + ;
		"Los demas comprobantes no se tocan.", "ZCFDIIMP - recargar")
		Return
	EndIf

	ImpBorra(cUuid)

	If ImpUno(cTxt, cNom, cRuta, cUuid, @cFalla)
		cMsg := "RECARGADO." + CRLF + CRLF
		cMsg += ImpCuadre(cTxt, cUuid)
	Else
		cMsg := "[!] NO SE PUDO RECARGAR, y el anterior ya se habia" + CRLF
		cMsg += "    borrado." + CRLF + CRLF
		cMsg += "    " + cFalla + CRLF + CRLF
		cMsg += "    Subelo otra vez con Importar." + CRLF
	EndIf

	U_ZCFDIREF()

Return ImpMues("Recargar", cMsg)

// ---------------------------------------------------------------------
// Borra un comprobante de las cuatro tablas del visor.
// ---------------------------------------------------------------------
Static Function ImpBorra(cUuid)
	Local aTab := {"ZCF", "ZCC", "ZCI", "ZCP", "ZCE", "ZCM", "ZCA", "ZCL", "ZCT", "ZCU", "ZCB", "ZCG"}
	Local nI   := 0
	Local cSuf := SubStr(AllTrim(RetSqlName("SF2")), 4)

	For nI := 1 To Len(aTab)
		TCSQLExec("DELETE FROM " + aTab[nI] + cSuf + ;
			" WHERE " + aTab[nI] + "_UUID = '" + cUuid + "'")
	Next nI

	// Los buffers abiertos siguen apuntando a renglones que ya no estan.
	For nI := 1 To Len(aTab)
		(aTab[nI])->(DbGoTop())
	Next nI

Return

// =====================================================================
// CUADRE: LO QUE TRAE EL XML CONTRA LO QUE QUEDO GUARDADO
//
// Contar en el TEXTO del xml no depende del parser, y eso es justo lo
// que se quiere: si el texto trae dos impuestos locales y en ZCI hay
// cero, el que fallo es el parser y no hay que adivinarlo.
// =====================================================================
Static Function ImpCuadre(cTxt, cUuid)
	Local nXml := 0
	Local nCpt := 0
	Local nImp := 0
	Local nLoc := 0
	Local cRet := ""

	nXml := ImpCuenta(cTxt, "implocal:TrasladosLocales") + ;
		ImpCuenta(cTxt, "implocal:RetencionesLocales")

	ZCC->(DbSetOrder(1))
	ZCC->(MsSeek(xFilial("ZCC") + cUuid))
	While !ZCC->(Eof()) .And. AllTrim(ZCC->ZCC_UUID) == AllTrim(cUuid)
		nCpt++
		ZCC->(DbSkip())
	EndDo

	ZCI->(DbSetOrder(1))
	ZCI->(MsSeek(xFilial("ZCI") + cUuid))
	While !ZCI->(Eof()) .And. AllTrim(ZCI->ZCI_UUID) == AllTrim(cUuid)
		If AllTrim(ZCI->ZCI_NIVEL) == "L"
			nLoc++
		Else
			nImp++
		EndIf
		ZCI->(DbSkip())
	EndDo

	cRet := "  Conceptos guardados        : " + cValToChar(nCpt) + CRLF
	cRet += "  Impuestos federales        : " + cValToChar(nImp) + CRLF
	cRet += "  Impuestos locales en el XML: " + cValToChar(nXml) + CRLF
	cRet += "  Impuestos locales guardados: " + cValToChar(nLoc) + CRLF

	Do Case
	Case nXml == 0
		cRet += CRLF + "  Este comprobante no trae impuestos locales." + CRLF
	Case nLoc == 0
		cRet += CRLF + "  [!] El XML SI trae locales y no se guardo ninguno." + CRLF
		cRet += "      El parser no esta encontrando los nodos." + CRLF
	Case nLoc < nXml
		cRet += CRLF + "  [!] Se guardaron menos de los que trae el XML." + CRLF
	EndCase

Return cRet

// ---------------------------------------------------------------------
// Cuantas veces abre una etiqueta en el texto del xml.
// ---------------------------------------------------------------------
Static Function ImpCuenta(cTxt, cTag)
	Local cBus := "<" + cTag
	Local cRes := cTxt
	Local nN   := 0
	Local nPos := 0

	nPos := At(cBus, cRes)
	Do While nPos > 0
		nN++
		cRes := SubStr(cRes, nPos + Len(cBus))
		nPos := At(cBus, cRes)
	EndDo

Return nN

// =====================================================================
// LO QUE LEE EL XML
// =====================================================================

// ---------------------------------------------------------------------
// Un nodo hijo, o NIL si no esta.
// ---------------------------------------------------------------------
Static Function ImpNodo(oPadre, cNom)
	Local oRet := NIL

	If oPadre != NIL
		oRet := XmlChildEx(oPadre, cNom)
	EndIf

Return oRet

// ---------------------------------------------------------------------
// El primer hijo que exista de una lista de nombres posibles. Sirve
// cuando no se sabe con que nombre quedo un nodo tras el parseo.
// ---------------------------------------------------------------------
Static Function ImpNodoAlt(oPadre, aNom)
	Local nI   := 0
	Local oRet := NIL

	If oPadre == NIL
		Return NIL
	EndIf

	For nI := 1 To Len(aNom)
		oRet := XmlChildEx(oPadre, aNom[nI])
		If oRet != NIL
			Return oRet
		EndIf
	Next nI

Return NIL

// ---------------------------------------------------------------------
// El valor de un atributo. En XmlParser los atributos son hijos con el
// texto en :TEXT, igual que los elementos.
//
// Nota: Si el atributo viene vacio, devuelve cadena vacia. Esa diferencia
// es importante para saber si fue omitido del XML (null) o si viene como
// cadena vacia, aunque hoy en la practica ambos casos se tratan igual
// ya que el XML no trae atributos vacios sino que omite el atributo.
// Si en el futuro necesitamos distinguir 0 de omitido, la marca estaria
// aqui.
// ---------------------------------------------------------------------
Static Function ImpAtr(oNodo, cAtr)
	Local oHij := NIL
	Local cRet := ""

	If oNodo == NIL
		Return ""
	EndIf

	oHij := XmlChildEx(oNodo, cAtr)

	If oHij != NIL .And. ValType(oHij) == "O"
		cRet := oHij:TEXT
	EndIf

Return AllTrim(cRet)

// ---------------------------------------------------------------------
// LA TRAMPA DEL PARSER
//
// XmlParser devuelve un OBJETO cuando el nodo aparece una vez y un
// ARREGLO cuando aparece varias. Esto normaliza las dos formas.
// ---------------------------------------------------------------------
Static Function ImpArr(xNodo)
	Local aRet := {}

	Do Case
	Case xNodo == NIL
		aRet := {}
	Case ValType(xNodo) == "A"
		aRet := xNodo
	Otherwise
		aRet := {xNodo}
	EndCase

Return aRet

// ---------------------------------------------------------------------
// Valor de un atributo buscandolo como texto. Se usa para el timbre,
// que vive dentro del complemento y cuya ruta de nodos varia mas que
// su forma.
// ---------------------------------------------------------------------
Static Function ImpStr(cTxt, cAtr)
	Local cBus := cAtr + '="'
	Local cRet := ""
	Local nPos := At(cBus, cTxt)
	Local nFin := 0

	If nPos > 0
		nPos += Len(cBus)
		nFin := At('"', SubStr(cTxt, nPos))
		If nFin > 1
			cRet := SubStr(cTxt, nPos, nFin - 1)
		EndIf
	EndIf

Return AllTrim(cRet)

// ---------------------------------------------------------------------
// "2026-07-01T11:36:47" -> fecha
// ---------------------------------------------------------------------
Static Function ImpFec(cFec)
	Local dRet := CToD("")

	If Len(AllTrim(cFec)) >= 10
		dRet := SToD(StrTran(SubStr(cFec, 1, 10), "-", ""))
	EndIf

Return dRet

// ---------------------------------------------------------------------
// ASIGNAR UNA FECHA SIN SUPONER EL TIPO DEL CAMPO
//
// Protheus lee el diccionario al ABRIR la sesion. Si las tablas se
// acaban de crear, la sesion todavia no conoce sus campos y abre la
// tabla con la estructura fisica -- donde una fecha es CHAR(8), porque
// asi las guarda Protheus. Meterle un valor de tipo fecha a ese campo
// truena con "Invalid data type".
//
// Se arregla saliendo y volviendo a entrar, pero el arreglo depende de
// que alguien se acuerde. Aqui se pregunta el tipo real del campo en
// este momento y se asigna lo que corresponda.
// ---------------------------------------------------------------------
Static Function ImpPonD(cAlias, cCampo, dVal)
	Local nPos := (cAlias)->(FieldPos(cCampo))

	If nPos == 0
		Return
	EndIf

	If ValType((cAlias)->(FieldGet(nPos))) == "D"
		(cAlias)->(FieldPut(nPos, dVal))
	Else
		(cAlias)->(FieldPut(nPos, IIf(Empty(dVal), "", DToS(dVal))))
	EndIf

Return

// ---------------------------------------------------------------------
// Lo mismo, pero recibiendo la fecha como viene en el XML.
// ---------------------------------------------------------------------
Static Function ImpPonF(cAlias, cCampo, cFec)
	ImpPonD(cAlias, cCampo, ImpFec(cFec))
Return

// =====================================================================
// CONVERTIR UN STRING A NUMERO, PRESERVANDO NULOS
//
// En el XML, un atributo ausente generaba ImpAtr() -> "" (cadena vacia).
// ImpNum("") devuelve 0, lo cual causa que campos opcionales se vean
// como 0.0000 en lugar de estar vacios.
//
// El problema es que Protheus no puede guardar NIL en un campo numerico.
// La solucion es guardar 0, pero MOSTRAR esos ceros especiales como
// cadena vacia en el detalle (ver VisNum en ZCFDIVIS.PRW). Aqui el
// parsing sigue siendo igual: convierte vacio a 0.
// =====================================================================
Static Function ImpNum(cVal)
	Local nRet := 0

	If !Empty(cVal)
		nRet := Val(AllTrim(cVal))
	EndIf

Return nRet

// ---------------------------------------------------------------------
// La especie sale del nombre del archivo: NF_A_000...XML -> NF
// Es lo que liga contra F2_ESPECIE sin tener que abrir el XML.
// ---------------------------------------------------------------------
Static Function ImpEspe(cNom)
	Local nPos := At("_", cNom)
	Local cRet := ""

	If nPos > 1
		cRet := SubStr(cNom, 1, nPos - 1)
	EndIf

Return SubStr(cRet, 1, 3)

// =====================================================================
// APOYO
// =====================================================================

// ---------------------------------------------------------------------
// Reporte de lo que el parser saco de un archivo. Sin grabar nada.
// ---------------------------------------------------------------------
Static Function ImpLee(cTxt, lDetalle)
	Local oXml := NIL
	Local oCom := NIL
	Local oCps := NIL
	Local cErr := ""
	Local cWrn := ""
	Local cRet := ""
	Local aCon := {}

	oXml := XmlParser(cTxt, "_", @cErr, @cWrn)

	If oXml == NIL
		Return "XmlParser devolvio NIL." + CRLF + "Error: " + cErr + CRLF
	EndIf

	If !Empty(cErr)
		cRet += "ERROR del parser: " + cErr + CRLF
	EndIf
	If !Empty(cWrn)
		cRet += "Aviso del parser: " + cWrn + CRLF
	EndIf

	oCom := ImpNodo(oXml, "_CFDI_COMPROBANTE")
	If oCom == NIL
		cRet += "No se hallo _CFDI_COMPROBANTE; se usa la raiz." + CRLF
		oCom := oXml
	EndIf

	cRet += CRLF + "CABECERA" + CRLF
	cRet += "  Version   : " + ImpAtr(oCom, "_VERSION") + CRLF
	cRet += "  Tipo      : " + ImpAtr(oCom, "_TIPODECOMPROBANTE") + CRLF
	cRet += "  Serie     : " + ImpAtr(oCom, "_SERIE") + CRLF
	cRet += "  Folio     : " + ImpAtr(oCom, "_FOLIO") + CRLF
	cRet += "  Fecha     : " + ImpAtr(oCom, "_FECHA") + CRLF
	cRet += "  Metodo    : " + ImpAtr(oCom, "_METODOPAGO") + CRLF
	cRet += "  Total     : " + ImpAtr(oCom, "_TOTAL") + CRLF

	cRet += CRLF + "EMISOR / RECEPTOR" + CRLF
	cRet += "  RFC emisor: " + ImpAtr(ImpNodo(oCom, "_CFDI_EMISOR"), "_RFC") + CRLF
	cRet += "  RFC recept: " + ImpAtr(ImpNodo(oCom, "_CFDI_RECEPTOR"), "_RFC") + CRLF
	cRet += "  Uso CFDI  : " + ImpAtr(ImpNodo(oCom, "_CFDI_RECEPTOR"), "_USOCFDI") + CRLF

	oCps := ImpNodo(oCom, "_CFDI_CONCEPTOS")
	aCon := ImpArr(ImpNodo(oCps, "_CFDI_CONCEPTO"))

	cRet += CRLF + "CONCEPTOS: " + cValToChar(Len(aCon)) + CRLF
	If Len(aCon) > 0
		cRet += "  1o clave  : " + ImpAtr(aCon[1], "_CLAVEPRODSERV") + CRLF
		cRet += "  1o descrip: " + SubStr(ImpAtr(aCon[1], "_DESCRIPCION"), 1, 40) + CRLF
		cRet += "  1o importe: " + ImpAtr(aCon[1], "_IMPORTE") + CRLF
	EndIf

	cRet += CRLF + "TIMBRE (leido por texto)" + CRLF
	cRet += "  UUID      : " + ImpStr(cTxt, "UUID") + CRLF
	cRet += "  Fecha timb: " + ImpStr(cTxt, "FechaTimbrado") + CRLF
	cRet += "  RFC PAC   : " + ImpStr(cTxt, "RfcProvCertif") + CRLF

	cRet += CRLF + "Si algun renglon sale vacio y en el XML SI viene," + CRLF
	cRet += "el nombre del nodo no es el que supuse." + CRLF

Return cRet

// ---------------------------------------------------------------------
// Vacia las cinco tablas del visor. Solo esas, y solo las que creamos
// nosotros. Los XML del servidor son la fuente y quedan intactos, asi
// que la carga se puede rearmar completa en cualquier momento.
// ---------------------------------------------------------------------
Static Function ImpVacia()
	Local aTab := {"ZCF", "ZCC", "ZCI", "ZCP", "ZCR", "ZCE", "ZCM", "ZCA", "ZCL", "ZCT", "ZCU", "ZCB", "ZCG"}
	Local nI   := 0
	Local cSuf := SubStr(AllTrim(RetSqlName("SF2")), 4)

	// El DELETE va por SQL, o sea por detras del alias que Protheus ya
	// tiene abierto. El area conserva su cache de indice, asi que un
	// MsSeek posterior sigue hallando renglones que la base ya borro:
	// el import los reportaba como "ya estaban por UUID" y se los
	// saltaba, dejando esos comprobantes fuera de la recarga.
	// Por eso se cierran las areas antes de borrar y se reabren despues.
	For nI := 1 To Len(aTab)
		If Select(aTab[nI]) > 0
			(aTab[nI])->(DbCloseArea())
		EndIf
	Next nI

	For nI := 1 To Len(aTab)
		TCSQLExec("DELETE FROM " + aTab[nI] + cSuf)
	Next nI

	For nI := 1 To Len(aTab)
		ChkFile(aTab[nI])
	Next nI

	// Cinturon: si el ambiente ignorara el cierre, esto tira el cache
	// de DBAccess de todos modos.
	For nI := 1 To Len(aTab)
		If Select(aTab[nI]) > 0
			(aTab[nI])->(DbGoTop())
		EndIf
	Next nI

Return

// ---------------------------------------------------------------------
// Un archivo que vive en ANULADAS es un comprobante cancelado.
// ---------------------------------------------------------------------
Static Function ImpEsAnu(cRuta)
Return "ANULADA" $ Upper(cRuta)

// ---------------------------------------------------------------------
// Marca un comprobante ya cargado como cancelado. Devuelve .T. si lo
// cambio; .F. si no lo hallo o si ya estaba marcado.
// ---------------------------------------------------------------------
Static Function ImpCanc(cUuid)
	ZCF->(DbSetOrder(1))

	If !ZCF->(MsSeek(xFilial("ZCF") + cUuid))
		Return .F.
	EndIf

	If AllTrim(ZCF->ZCF_ESTSAT) == "C"
		Return .F.
	EndIf

	RecLock("ZCF", .F.)
	ZCF->ZCF_ESTSAT := "C"
	ZCF->(MsUnlock())

Return .T.

// ---------------------------------------------------------------------
Static Function ImpHayUu(cUuid)
	Local lRet := .F.

	ZCF->(DbSetOrder(1))
	lRet := ZCF->(MsSeek(xFilial("ZCF") + cUuid))

Return lRet

// ---------------------------------------------------------------------
Static Function ImpAbre()
	Local aArq := {"ZCF", "ZCC", "ZCI", "ZCP", "ZCR", "ZCE", "ZCM", "ZCA", "ZCL", "ZCT", "ZCU", "ZCB", "ZCG"}
	Local nI   := 0

	For nI := 1 To Len(aArq)
		If Select(aArq[nI]) == 0
			If !ChkFile(aArq[nI])
				MsgStop("No se pudo abrir " + aArq[nI] + "." + CRLF + CRLF + ;
					"Si las tablas se acaban de crear, hay que salir del" + CRLF + ;
					"modulo y volver a entrar: Protheus lee el diccionario" + CRLF + ;
					"al abrir la sesion.", "ZCFDIIMP")
				Return .F.
			EndIf
		EndIf
	Next nI

Return .T.

// ---------------------------------------------------------------------
// Carpetas de CFD con XML. Recorrido propio para no depender de ZCFDI.
// ---------------------------------------------------------------------
Static Function ImpCarp(aCar)
	ImpAnda("\", 1, @aCar)
Return

// ---------------------------------------------------------------------
Static Function ImpAnda(cRuta, nNiv, aCar)
	Local aDir := {}
	Local nI   := 0
	Local cSub := ""

	If nNiv > 4
		Return
	EndIf

	aDir := Directory(cRuta + "*.*", "D")

	For nI := 1 To Len(aDir)
		If "D" $ aDir[nI][5] .And. aDir[nI][1] != "." .And. aDir[nI][1] != ".."
			cSub := cRuta + AllTrim(aDir[nI][1]) + "\"

			If "CFD" $ Upper(cSub) .And. Len(Directory(cSub + "*.xml")) > 0
				aAdd(aCar, cSub)
			EndIf

			ImpAnda(cSub, nNiv + 1, @aCar)
		EndIf
	Next nI

Return

// =====================================================================
// EMITIDO O RECIBIDO
//
// Antes esto estaba clavado a "E" para todo, con un comentario que
// decia "los recibidos vendran despues". Ya vinieron.
//
// La regla es simple: si el RFC del EMISOR es uno de los nuestros, el
// comprobante lo emitimos nosotros. Si no, alguien nos lo emitio a
// nosotros.
//
// De donde salen "los nuestros":
//
//   1. De SM0 -- el archivo de empresas de Protheus. Se recorren TODAS
//      las filiales, no solo la actual, porque un grupo puede tener
//      varias con RFC distinto y una factura entre filiales no es un
//      "recibido" de un tercero.
//   2. Del parametro MV_ZCFRFC, por si hace falta agregar alguno que no
//      este en SM0 (una razon social que factura desde otro sistema,
//      por ejemplo). Varios RFC separados por coma.
//
// Si por lo que sea no se pudo armar la lista, se devuelve "?" en vez
// de adivinar. Un dato en blanco se nota; un dato inventado no.
// =====================================================================

/*/{Protheus.doc} ZCFORIG
Devuelve "E" (emitido), "R" (recibido) o "?" (no se pudo determinar).
@param cRfcEmi RFC que viene en el nodo Emisor del CFDI
/*/
User Function ZCFORIG(cRfcEmi)
	Local aRfc := ImpRfcs()
	Local cRfc := ImpNorm(cRfcEmi)

	If Len(aRfc) == 0 .Or. Empty(cRfc)
		Return "?"
	EndIf

Return IIf(aScan(aRfc, {|x| x == cRfc}) > 0, "E", "R")

// ---------------------------------------------------------------------
// Un RFC comparable: mayusculas y sin espacios, guiones ni puntos.
// El SAT no los trae, pero un parametro capturado a mano si.
// ---------------------------------------------------------------------
Static Function ImpNorm(cRfc)
	Local cRet := Upper(AllTrim(cValToChar(cRfc)))

	cRet := StrTran(cRet, "-", "")
	cRet := StrTran(cRet, ".", "")
	cRet := StrTran(cRet, " ", "")

Return cRet

// ---------------------------------------------------------------------
// Los RFC de la casa. Se arma una vez por sesion.
// ---------------------------------------------------------------------
Static Function ImpRfcs()
	Local aRet := {}
	Local cPar := ""
	Local aPar := {}
	Local nRec := 0
	Local nI   := 0
	Local cR   := ""

	If _aRfcCasa != NIL
		Return _aRfcCasa
	EndIf

	// --- SM0: todas las filiales ---
	//
	// OJO: hay que devolver SM0 a donde estaba. El resto de Protheus da
	// por hecho que SM0 esta parado en la empresa/filial de la sesion, y
	// dejarlo movido rompe cosas lejos de aqui y dificiles de relacionar
	// con este fuente.
	If Select("SM0") > 0
		nRec := SM0->(Recno())
		SM0->(DbGoTop())
		While !SM0->(Eof())
			cR := ImpNorm(SM0->M0_CGC)
			If !Empty(cR) .And. aScan(aRet, {|x| x == cR}) == 0
				aAdd(aRet, cR)
			EndIf
			SM0->(DbSkip())
		EndDo
		SM0->(DbGoTo(nRec))
	EndIf

	// --- MV_ZCFRFC: los que haga falta agregar a mano ---
	cPar := AllTrim(cValToChar(GetNewPar("MV_ZCFRFC", "")))
	If !Empty(cPar)
		aPar := StrTokArr(cPar, ",")
		For nI := 1 To Len(aPar)
			cR := ImpNorm(aPar[nI])
			If !Empty(cR) .And. aScan(aRet, {|x| x == cR}) == 0
				aAdd(aRet, cR)
			EndIf
		Next nI
	EndIf

	_aRfcCasa := aRet

Return aRet

/*/{Protheus.doc} ZCFDIORI
Recalcula el origen de TODO lo que ya esta cargado en ZCF.

Hace falta porque los comprobantes importados antes de esto quedaron
marcados como emitidos sin que nadie lo comprobara. Se puede volver a
correr cuantas veces se quiera: siempre llega al mismo resultado.
/*/
User Function ZCFDIORI()
	Local nE  := 0
	Local nR  := 0
	Local nD  := 0
	Local cOr := ""
	Local aRfc := {}

	If Select("ZCF") == 0
		If !ChkFile("ZCF")
			MsgStop("No se pudo abrir ZCF.", "ZCFDIORI")
			Return
		EndIf
	EndIf

	_aRfcCasa := NIL     // por si cambio el parametro desde que se abrio
	aRfc := ImpRfcs()

	If Len(aRfc) == 0
		MsgStop("No se pudo determinar el RFC de la empresa." + CRLF + CRLF + ;
			"Se busco en SM0 y en el parametro MV_ZCFRFC y no se" + CRLF + ;
			"encontro ninguno. Sin eso no hay forma de saber que" + CRLF + ;
			"comprobante lo emitimos nosotros.", "ZCFDIORI")
		Return
	EndIf

	If !MsgYesNo("Se va a revisar el origen de cada comprobante." + CRLF + CRLF + ;
		"RFC de la casa: " + aRfc[1] + ;
		IIf(Len(aRfc) > 1, " (y " + cValToChar(Len(aRfc) - 1) + " mas)", "") + CRLF + CRLF + ;
		"CONTINUAR?", "ZCFDIORI")
		Return
	EndIf

	ZCF->(DbGoTop())
	While !ZCF->(Eof())

		cOr := U_ZCFORIG(ZCF->ZCF_EMIRFC)

		If cOr != ZCF->ZCF_ORIGEN
			RecLock("ZCF", .F.)
			ZCF->ZCF_ORIGEN := cOr
			ZCF->(MsUnlock())
		EndIf

		Do Case
		Case cOr == "E" ; nE++
		Case cOr == "R" ; nR++
		Otherwise       ; nD++
		EndCase

		ZCF->(DbSkip())
	EndDo

	ZCF->(DbGoTop())

	MsgInfo("ORIGEN RECALCULADO" + CRLF + CRLF + ;
		"  Emitidos      : " + Str(nE, 6) + CRLF + ;
		"  Recibidos     : " + Str(nR, 6) + CRLF + ;
		"  Indeterminados: " + Str(nD, 6), "ZCFDIORI")

Return

// ---------------------------------------------------------------------
// Escribe un campo SOLO si existe en la tabla.
//
// Los campos nuevos se agregan a la tabla con Construir - Crear tablas.
// Mientras alguien no haya corrido eso, el campo no existe y asignarlo
// truena. Preguntar primero cuesta nada y deja que el importador nuevo
// conviva con una tabla vieja.
//
// Esta funcion FALTABA y por eso reventaba con NOFUNCW. Se inserto en
// su momento buscando un comentario que resulto estar escrito con otro
// separador, la busqueda no encontro nada, y la insercion se fue en
// silencio. Por eso ahora todo cambio lleva verificacion: una
// sustitucion que no encuentra su ancla tiene que fallar ruidosamente,
// no pasar de largo.
// ---------------------------------------------------------------------
Static Function ImpPonC(cAlias, cCampo, cValor)
	Local nPos := (cAlias)->(FieldPos(cCampo))

	If nPos > 0
		(cAlias)->(FieldPut(nPos, cValor))
		Return
	EndIf

	// Saltarse un campo que no existe evita que el import truene, pero
	// callarselo es peor que tronar: el comprobante entra incompleto y
	// nadie se entera hasta que alguien revisa una columna vacia en el
	// Excel. Eso ya paso con ZCF_RECNRT y costo una tarde. Se deja
	// constancia y el resumen final la reporta.
	_ImpAnota(cCampo)

	// Y ademas se guarda igual. Que la SESION no vea el campo no quiere
	// decir que el campo no exista: el diccionario se lee al abrir la
	// sesion, asi que una columna creada despues es invisible para
	// FieldPos aunque este en Oracle y en el SX3. Reiniciar Protheus
	// deberia arreglarlo y a veces no alcanza, porque el AppServer
	// tambien cachea. Como el dato SI cabe en la tabla fisica, se
	// apunta el renglon y al final del import se escribe por SQL
	// directo, sin pasar por el alias.
	_ImpCola(cAlias, (cAlias)->(Recno()), cCampo, cValor)

Return

// ---------------------------------------------------------------------
// Lo mismo que ImpPonC pero para campos numericos. Se separa en vez de
// resolverlo con un ValType adentro porque quien llama SI sabe que esta
// guardando, y un numero que llega como texto por descuido se nota aqui
// y no tres pantallas despues.
// ---------------------------------------------------------------------
Static Function ImpPonN(cAlias, cCampo, nValor)
	Local nPos := (cAlias)->(FieldPos(cCampo))

	If nPos > 0
		(cAlias)->(FieldPut(nPos, nValor))
		Return
	EndIf

	_ImpAnota(cCampo)
	_ImpCola(cAlias, (cAlias)->(Recno()), cCampo, nValor)

Return

// ---------------------------------------------------------------------
// Lleva la lista de campos que no existian en la tabla abierta. Es una
// STATIC de archivo a proposito: la anotacion ocurre en lo hondo del
// parser y el reporte sale al final, y pasarla de mano en mano por diez
// funciones solo para eso no vale la pena.
// ---------------------------------------------------------------------
Static _aImpFal := {}

Static Function _ImpAnota(cCampo)
	If aScan(_aImpFal, {|x| x == cCampo }) == 0
		aAdd(_aImpFal, cCampo)
	EndIf
Return

Static Function _ImpLimpia()
	_aImpFal := {}
	_aImpSql := {}
	_aImpSin := {}
Return

Static Function _ImpFaltan()
Return _aImpFal

// ---------------------------------------------------------------------
// Cola de escrituras que el alias no pudo hacer y se resuelven por SQL
// directo al terminar el import. Cada renglon es
// {alias, recno, campo, valor}. Se escribe hasta el final a proposito:
// mientras el import corre el registro todavia puede estar en el buffer
// del RecLock y un UPDATE lo pisaria o no lo encontraria.
// ---------------------------------------------------------------------
Static _aImpSql := {}

Static Function _ImpCola(cAlias, nRec, cCampo, cValor)
	If nRec == nil .Or. nRec <= 0
		Return
	EndIf

	// Un valor vacio no se encola: no hay nada que escribir, la columna
	// ya trae su valor por omision. Y ademas tronaba: en Oracle la
	// cadena vacia ES NULL, asi que "SET campo = ''" choca contra el
	// NOT NULL de la columna con ORA-01407. De 150 encolados, 120 eran
	// vacios -- un XML sin NumRegIdTrib no es un dato que se perdio,
	// es un dato que no existe.
	If Empty(cValor)
		Return
	EndIf

	aAdd(_aImpSql, {cAlias, nRec, cCampo, cValor})
Return

// ---------------------------------------------------------------------
// Vacia la cola escribiendo cada valor con un UPDATE por R_E_C_N_O_.
// Devuelve cuantos renglones se escribieron. Las comillas simples del
// valor se duplican: es la unica forma de que un nombre con apostrofe
// no rompa el SQL.
// ---------------------------------------------------------------------
Static Function _ImpSqlFl()
	Local nI    := 0
	Local nOk   := 0
	Local nErr  := 0
	Local nRet  := 0
	Local cTab  := ""
	Local cVal  := ""
	Local cSql  := ""
	Local cRet  := ""
	Local cEjem := ""
	Local cErr  := ""
	Local aPar  := {}
	Local nPos  := 0

	If Len(_aImpSql) == 0
		Return ""
	EndIf

	For nI := 1 To Len(_aImpSql)
		cTab := AllTrim(RetSqlName(_aImpSql[nI][1]))

		// Un numero NO lleva comillas y un texto SI, y ademas hay que
		// doblar las comillas simples del texto para que un valor con
		// apostrofe no rompa el SQL.
		If ValType(_aImpSql[nI][4]) == "N"
			cVal := cValToChar(_aImpSql[nI][4])
		Else
			cVal := "'" + StrTran(cValToChar(_aImpSql[nI][4]), "'", "''") + "'"
		EndIf

		cSql := "UPDATE " + cTab + ;
			" SET " + _aImpSql[nI][3] + " = " + cVal + ;
			" WHERE R_E_C_N_O_ = " + cValToChar(_aImpSql[nI][2])

		If Empty(cEjem)
			cEjem := cSql
		EndIf

		nRet := TCSQLExec(cSql)
		If nRet == 0
			nOk++
		Else
			nErr++
			If Empty(cErr)
				cErr := cValToChar(TCSQLError())
			EndIf
		EndIf

		// guardar el par alias/campo para verificarlo despues
		nPos := aScan(aPar, {|x| x[1] == _aImpSql[nI][1] .And. x[2] == _aImpSql[nI][3] })
		If nPos == 0
			aAdd(aPar, {_aImpSql[nI][1], _aImpSql[nI][3], ;
				ValType(_aImpSql[nI][4])})
		EndIf
	Next nI

	cRet += "  escritos por SQL directo : " + cValToChar(nOk) + CRLF
	cRet += "  (los campos vacios no se escriben: no hay nada que" + CRLF
	cRet += "   guardar y el UPDATE a NULL truena con ORA-01407)" + CRLF
	If nErr > 0
		cRet += "  FALLARON                 : " + cValToChar(nErr) + CRLF
		cRet += "     " + cErr + CRLF
	EndIf

	// Un UPDATE que no encuentra su renglon tambien devuelve 0, asi que
	// contar statements que corrieron NO prueba que se haya escrito
	// nada. La unica prueba es volver a preguntarle a la base.
	// Ojo: en Oracle la cadena vacia ES NULL, por eso aqui basta
	// IS NOT NULL -- agregarle un <> '' tira todas las filas y el
	// contador sale 0 siempre.
	cRet += "  comprobacion en la base  :" + CRLF
	For nI := 1 To Len(aPar)
		// En una columna numerica "IS NOT NULL" cuenta tambien los
		// ceros que dejo el ALTER TABLE, y entonces una columna vacia
		// reporta la tabla entera. Para numericos se cuenta <> 0.
		If aPar[nI][3] == "N"
			cSql := "SELECT COUNT(*) AS TOT FROM " + ;
				AllTrim(RetSqlName(aPar[nI][1])) + ;
				" WHERE D_E_L_E_T_ = ' ' AND " + AllTrim(aPar[nI][2]) + " <> 0"
		Else
			cSql := "SELECT COUNT(*) AS TOT FROM " + ;
				AllTrim(RetSqlName(aPar[nI][1])) + ;
				" WHERE D_E_L_E_T_ = ' ' AND TRIM(" + AllTrim(aPar[nI][2]) + ") IS NOT NULL"
		EndIf
		TCQuery cSql New Alias "QV"
		QV->(DbGoTop())
		cRet += "     " + aPar[nI][2] + ": " + cValToChar(QV->TOT) + " renglon(es)" + ;
			IIf(aPar[nI][3] == "N", " con valor <> 0", "") + CRLF
		QV->(DbCloseArea())
	Next nI

	If nOk > 0
		cRet += "  ejemplo del UPDATE:" + CRLF
		cRet += "     " + cEjem + CRLF
	EndIf

	_aImpSql := {}

Return cRet

// ---------------------------------------------------------------------
// LOS XML SIN TIMBRE
//
// De los archivos del acervo de prueba, algunos no traen
// TimbreFiscalDigital. El numero solo no dice nada; lo que se necesita
// saber es en que paso se quedo cada uno:
//
//   CON Sello y SIN timbre -> Protheus lo genero y lo sello con el
//                             certificado de la empresa, y el PAC
//                             nunca devolvio el timbre. El comprobante
//                             existe, le falta el ultimo paso.
//   SIN Sello              -> ni siquiera llego a sellarse.
//
// La distincion importa porque las dos se arreglan en lugares
// distintos, y porque la primera es la misma forma que tienen las
// ciertas facturas que salieron sin folio fiscal.
//
// Los _ORIGIN NO llegan aqui: se descartan antes por el nombre. Lo que
// entra a este reporte son archivos de nombre normal.
// ---------------------------------------------------------------------
Static _aImpSin := {}

Static Function _ImpSinAn(cNom, cCar, cTxt)
	Local lSel := !Empty(ImpStr(cTxt, "Sello"))

	aAdd(_aImpSin, {cNom, cCar, ;
		ImpStr(cTxt, "Serie"), ;
		ImpStr(cTxt, "Folio"), ;
		Left(ImpStr(cTxt, "Fecha"), 10), ;
		ImpStr(cTxt, "TipoDeComprobante"), ;
		ImpStr(cTxt, "Total"), ;
		lSel})

Return

Static Function _ImpSinRep()
	Local cRep := ""
	Local nI   := 0
	Local nSel := 0
	Local nNad := 0
	Local cArq := ""

	If Len(_aImpSin) == 0
		Return ""
	EndIf

	For nI := 1 To Len(_aImpSin)
		If _aImpSin[nI][8]
			nSel++
		Else
			nNad++
		EndIf
	Next nI

	cRep := "--- XML SIN TIMBRE FISCAL ---" + CRLF + CRLF
	cRep += "  Fecha de la corrida : " + DToC(Date()) + " " + Time() + CRLF
	cRep += "  Archivos sin timbre : " + cValToChar(Len(_aImpSin)) + CRLF
	cRep += "     con Sello        : " + cValToChar(nSel) + ;
		"   (sellados, el PAC no devolvio el timbre)" + CRLF
	cRep += "     sin Sello        : " + cValToChar(nNad) + ;
		"   (no llegaron a sellarse)" + CRLF + CRLF
	cRep += "  No se cuentan los _ORIGIN: esos son copias previas al" + CRLF
	cRep += "  timbrado del mismo comprobante y se descartan antes." + CRLF + CRLF

	cRep += _ImpSinSF2() + CRLF

	cArq := _ImpEscr(cRep)

Return "Reporte de los sin timbre:" + CRLF + "  " + cArq

// ---------------------------------------------------------------------
// EL CRUCE CONTRA SF2 -- LA PREGUNTA QUE EL XML NO PUEDE CONTESTAR
//
// Un XML sin timbre en la carpeta NO prueba que la factura se haya
// quedado sin timbrar. Pudo timbrarse despues por otra via y el archivo
// del disco quedo viejo. Lo que lo decide es F2_UUID en SF2:
//
//   esta en SF2 y F2_UUID lleno  -> la factura SI acabo timbrada.
//                                   El XML del disco es una copia vieja,
//                                   no un problema.
//   esta en SF2 y F2_UUID vacio  -> la factura existe y NO tiene folio
//                                   fiscal. Este si es el problema.
//   no esta en SF2               -> el XML no corresponde a un documento
//                                   vivo: cancelado, borrado o de prueba.
//
// Se lee SF2 de una sola vez a un arreglo y se busca en memoria. Son
// 50 archivos contra unos cientos de documentos; una consulta por
// archivo seria mas lenta y no mas clara.
//
// El folio se compara SIN ceros a la izquierda: los nombres de archivo
// no traen el mismo ancho ("0000000000000001" y "0000000004" conviven
// en la misma carpeta) y F2_DOC tiene el suyo propio.
// ---------------------------------------------------------------------
Static Function _ImpSinSF2()
	Local cRet := ""
	Local aDoc := {}
	Local nI   := 0
	Local nPos := 0
	Local nTim := 0
	Local nNoT := 0
	Local nAus := 0
	Local nMon := 0
	Local cEsp := ""
	Local cSer := ""
	Local cDoc := ""
	Local cUui := ""

	aDoc := _ImpSF2Car()

	If Len(aDoc) == 0
		Return "  (no se pudo leer SF2: el cruce queda pendiente)" + CRLF
	EndIf

	cRet := "  ARCHIVO                              SER FOLIO            " + ;
		"FECHA       TIPO TOTAL          SELLO EN SF2   FOLIO FISCAL" + CRLF
	cRet += Replicate("-", 132) + CRLF

	For nI := 1 To Len(_aImpSin)
		cEsp := _ImpEspec(_aImpSin[nI][1])
		cSer := _aImpSin[nI][3]
		cDoc := _ImpSinCer(_aImpSin[nI][4])

		nPos := aScan(aDoc, {|x| x[1] == cEsp .And. x[2] == cSer .And. ;
			x[3] == cDoc })

		If nPos == 0
			cUui := "no esta"
			nAus++
		ElseIf !Empty(aDoc[nPos][4])
			cUui := "SI: " + Left(aDoc[nPos][4], 8) + "..."
			nTim++
		Else
			cUui := ">> VACIO <<"
			nNoT++
			nMon += Val(StrTran(_aImpSin[nI][7], ",", ""))
		EndIf

		cRet += "  " + PadR(_aImpSin[nI][1], 36) + " " + ;
			PadR(cSer, 3) + " " + ;
			PadR(_aImpSin[nI][4], 16) + " " + ;
			PadR(_aImpSin[nI][5], 11) + " " + ;
			PadR(_aImpSin[nI][6], 4) + " " + ;
			PadL(_aImpSin[nI][7], 14) + " " + ;
			PadR(IIf(_aImpSin[nI][8], "SI", "no"), 5) + " " + ;
			PadR(IIf(nPos > 0, "si", "NO"), 7) + " " + cUui + CRLF
	Next nI

	cRet += CRLF
	cRet += "  --- RESUMEN DEL CRUCE CONTRA SF2 ---" + CRLF + CRLF
	cRet += "  Se timbraron despues (F2_UUID lleno) : " + ;
		cValToChar(nTim) + CRLF
	cRet += "     El XML del disco es copia vieja. No es problema." + CRLF + CRLF
	cRet += "  SIN folio fiscal en SF2              : " + ;
		cValToChar(nNoT) + CRLF
	cRet += "     Estos si son facturas sin timbrar." + CRLF
	cRet += "     Suma: " + Transform(nMon, "@E 999,999,999.99") + CRLF + CRLF
	cRet += "  No existen en SF2                    : " + ;
		cValToChar(nAus) + CRLF
	cRet += "     Cancelados, borrados o pruebas que no dejaron" + CRLF
	cRet += "     documento. No se pueden juzgar desde aqui." + CRLF

Return cRet

// ---------------------------------------------------------------------
// Lee SF2 una vez: {especie, serie, folio sin ceros, uuid}
// ---------------------------------------------------------------------
Static Function _ImpSF2Car()
	Local aRet := {}
	Local cAli := GetNextAlias()
	Local cQry := ""

	cQry := "SELECT F2_ESPECIE, F2_SERIE, F2_DOC, F2_UUID "
	cQry += "  FROM " + RetSqlName("SF2") + " "
	cQry += " WHERE D_E_L_E_T_ = ' ' "

	TCQuery cQry New Alias (cAli)

	Do While !(cAli)->(Eof())
		aAdd(aRet, {AllTrim((cAli)->F2_ESPECIE), ;
			AllTrim((cAli)->F2_SERIE), ;
			_ImpSinCer((cAli)->F2_DOC), ;
			AllTrim((cAli)->F2_UUID)})
		(cAli)->(DbSkip())
	EndDo

	(cAli)->(DbCloseArea())

Return aRet

// ---------------------------------------------------------------------
// La especie sale del nombre del archivo: NF_A_000...  -> NF
//                                         NCC_NCC_000... -> NCC
// Lo que va antes del primer guion bajo.
// ---------------------------------------------------------------------
Static Function _ImpEspec(cNom)
	Local nPos := At("_", cNom)

	If nPos <= 1
		Return ""
	EndIf

Return AllTrim(SubStr(cNom, 1, nPos - 1))

// Quita ceros a la izquierda para poder comparar folios de distinto ancho
Static Function _ImpSinCer(cDoc)
	Local cRet := AllTrim(cValToChar(cDoc))

	Do While Len(cRet) > 1 .And. Left(cRet, 1) == "0"
		cRet := SubStr(cRet, 2)
	EndDo

Return cRet

// ---------------------------------------------------------------------
// Deja el reporte donde se pueda leer sin entrar al servidor. Mismo
// camino que usa ZCFDINOD para el censo: se escribe en el servidor y se
// copia a la maquina.
//
// OJO con CpyS2T: el destino es una CARPETA, no la ruta del archivo.
// ---------------------------------------------------------------------
Static Function _ImpEscr(cRep)
	Local cDir  := "\zcfdi\"
	Local cNom  := "sin_timbre_" + DToS(Date()) + "_" + ;
		StrTran(Left(Time(), 5), ":", "") + ".txt"
	Local cArq  := cDir + cNom
	Local cDest := "C:\TOTVS\anexo20csv\"
	Local nH    := 0

	If !ExistDir(cDir)
		MakeDir(cDir)
	EndIf

	nH := FCreate(cArq)
	If nH < 0
		Return "(no se pudo crear el archivo)"
	EndIf

	FWrite(nH, cRep)
	FClose(nH)

	CpyS2T(cArq, cDest)

Return cDest + cNom
