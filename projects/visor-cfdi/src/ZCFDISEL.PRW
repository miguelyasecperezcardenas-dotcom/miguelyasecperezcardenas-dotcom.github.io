#INCLUDE "PROTHEUS.CH"
#INCLUDE "TOPCONN.CH"

/*/{Protheus.doc} ZCFDISEL
Complementos de pago que quedaron a medio camino.

QUE BUSCA

Recibos de cobranza que YA TIENEN folio fiscal pero NO tienen fecha de
timbrado. Se les genero el folio y nunca se completo el sellado, asi que
el SAT no los tiene. Son comprobantes a medio emitir: existen para
Protheus y no existen para el SAT.

En una medicion en produccion salieron varios casos. Este es el hilo
que quedo pendiente de aquella revision.

POR QUE NO SALE DEL VISOR

El visor lee ZCF, que se llena importando XML de una carpeta. Un recibo
sin sellar NO tiene XML -- por eso quedo sin sellar. Nunca va a aparecer
ahi por mas que se importe.

Hay que preguntarle a SEL, la tabla de recibos de cobranza, que es donde
vive el complemento de pago en Protheus. El complemento no nace de la
factura sino del COBRO, y por eso no esta en SF2.

SE CUENTAN FOLIOS, NO RENGLONES

Un recibo de cobranza ocupa varios renglones en SEL: uno EL_TIPO='NF'
con la factura que se paga, otro EL_TIPO='TF' con la transferencia, y
mas si liquida varias facturas. Todos comparten el MISMO EL_UUID.

Contar renglones reporta casi el doble. Fue el error que ya se cometio
una vez en este proyecto: los "22 sin sellar" resultaron ser 11 folios
repetidos hasta que se conto DISTINCT. El complemento de pago es el
CFDI, y el CFDI es el folio fiscal.

SOLO LEE

No escribe nada, en ningun lado. Sellar un comprobante no es algo que
esta rutina deba hacer por su cuenta.

@author Claude + Miguel Yasec
@since 09/2026
/*/
User Function ZCFDISEL()
	Local cTxt := ""

	cTxt := SelRepo()

	SelMues("Complementos de pago sin sellar", cTxt)

Return

// ---------------------------------------------------------------------
Static Function SelRepo()
	Local cRet := ""
	Local cTab := ""
	Local aCpo := {}

	cTab := SelTab("SEL")

	// El nombre resuelto va en el encabezado a proposito: es la unica
	// forma de confirmar de un vistazo que se leyo la tabla del ambiente
	// correcto y no una homonima de otro.
	cRet += "Tabla leida: " + cTab + CRLF
	cRet += "Ambiente   : " + AllTrim(cValToChar(GetEnvServer())) + CRLF + CRLF

	If !SelHay()
		cRet += "No se pudo abrir SEL en este ambiente." + CRLF + CRLF
		cRet += "SEL es la tabla de recibos de cobranza. Si no abre, o el" + CRLF
		cRet += "modulo no la tiene, o el usuario no tiene acceso." + CRLF
		Return cRet
	EndIf

	aCpo := SelCpos()

	cRet += SelCuenta(cTab)
	cRet += SelLista(cTab, aCpo)

Return cRet

// ---------------------------------------------------------------------
// El conteo. Todo DISTINCT sobre el folio fiscal.
// ---------------------------------------------------------------------
Static Function SelCuenta(cTab)
	Local cRet := ""
	Local cSql := ""
	Local nUid := 0
	Local nTim := 0

	cSql := "SELECT COUNT(*) AS TOTREG, "
	cSql += "COUNT(DISTINCT TRIM(EL_UUID)) AS CONUID, "
	cSql += "COUNT(DISTINCT CASE WHEN TRIM(EL_FECTIMB) IS NOT NULL "
	cSql += "THEN TRIM(EL_UUID) END) AS CONTIM "
	cSql += "FROM " + cTab + " WHERE D_E_L_E_T_ = ' '"

	TCQuery cSql New Alias "QS"

	QS->(DbGoTop())

	If QS->(Eof())
		cRet += "(no se pudo leer SEL)" + CRLF
	Else
		nUid := QS->CONUID
		nTim := QS->CONTIM

		cRet += "=== RECIBOS DE COBRANZA ===" + CRLF + CRLF
		cRet += "  Renglones en SEL          : " + Str(QS->TOTREG, 7) + ;
			"   (un recibo ocupa varios)" + CRLF
		cRet += "  Complementos con folio    : " + Str(nUid, 7) + CRLF
		cRet += "  Complementos timbrados    : " + Str(nTim, 7) + CRLF
		cRet += "  CON FOLIO Y SIN SELLAR    : " + Str(nUid - nTim, 7) + ;
			IIf(nUid > nTim, "   <- son estos", "") + CRLF + CRLF

		If nUid == nTim
			cRet += "  Todo lo que tiene folio esta sellado. Nada que" + CRLF
			cRet += "  revisar por este lado." + CRLF + CRLF
		EndIf
	EndIf

	QS->(DbCloseArea())

Return cRet

// ---------------------------------------------------------------------
// El detalle, para poder ir a buscarlos.
//
// Las columnas se arman con los campos que SI existan en este ambiente.
// EL_UUID, EL_PREFIXO y EL_FECTIMB son seguros porque ya se usan en
// ANX20REP; del resto no hay garantia, y una consulta que nombra un
// campo inexistente no devuelve menos datos: truena entera. Por eso se
// pregunta antes con FieldPos en vez de confiar.
// ---------------------------------------------------------------------
Static Function SelLista(cTab, aCpo)
	Local cRet := ""
	Local cSql := ""
	Local cCol := ""
	Local nI   := 0
	Local nN   := 0

	For nI := 1 To Len(aCpo)
		cCol += ", MIN(TRIM(" + aCpo[nI] + "))"
	Next nI

	// GROUP BY, NO DISTINCT  (corregido el 28/09/2026)
	//
	// La primera version hacia SELECT DISTINCT sobre folio + serie + el
	// resto de las columnas. Eso NO deduplica por folio: basta con que
	// una columna cambie entre renglones para que el mismo folio salga
	// dos veces. Y cambia -- los renglones de un recibo traen prefijos
	// distintos ('A' en el de la factura, 'TF' en el de la
	// transferencia).
	//
	// El resultado fue un reporte que se contradecia solo: el
	// encabezado contaba 11 folios y el detalle listaba 22 renglones
	// como si fueran 22 complementos. Es el mismo error de contar
	// renglones en vez de folios que ya estaba documentado, colado por
	// la puerta de atras.
	//
	// Agrupando por folio y tomando MIN del resto, cada complemento
	// ocupa exactamente un renglon y el detalle cuadra con el conteo.
	cSql := "SELECT TRIM(EL_UUID) AS UUID, "
	cSql += "MIN(TRIM(EL_PREFIXO)) AS SERIE" + cCol + " "
	cSql += "FROM " + cTab + " "
	cSql += "WHERE D_E_L_E_T_ = ' ' "
	cSql += "AND TRIM(EL_UUID) IS NOT NULL "
	cSql += "AND TRIM(EL_FECTIMB) IS NULL "
	cSql += "GROUP BY TRIM(EL_UUID) "
	cSql += "ORDER BY 1"

	TCQuery cSql New Alias "QL"

	QL->(DbGoTop())

	If QL->(Eof())
		QL->(DbCloseArea())
		Return cRet
	EndIf

	cRet += "=== DETALLE ===" + CRLF + CRLF
	cRet += "  " + PadR("Folio fiscal", 38) + PadR("Serie", 8)
	For nI := 1 To Len(aCpo)
		cRet += PadR(SubStr(aCpo[nI], 4), 14)
	Next nI
	cRet += CRLF + "  " + Replicate("-", 46 + Len(aCpo) * 14) + CRLF

	Do While !QL->(Eof())
		nN++
		cRet += "  " + PadR(AllTrim(QL->UUID), 38) + ;
			PadR(AllTrim(cValToChar(QL->SERIE)), 8)
		For nI := 1 To Len(aCpo)
			cRet += PadR(AllTrim(cValToChar(QL->(FieldGet(nI + 2)))), 14)
		Next nI
		cRet += CRLF
		QL->(DbSkip())
	EndDo

	QL->(DbCloseArea())

	cRet += CRLF + "  " + cValToChar(nN) + " complemento(s) con folio y sin sellar." + CRLF + CRLF
	cRet += "  QUE SIGNIFICA" + CRLF + CRLF
	cRet += "  A cada uno se le aparto un folio fiscal y nunca se" + CRLF
	cRet += "  completo el timbrado. El SAT no los tiene. Para el" + CRLF
	cRet += "  cliente que pago, ese complemento no existe." + CRLF + CRLF
	cRet += "  Esta rutina SOLO LEE. No sella nada: hay que revisar" + CRLF
	cRet += "  uno por uno por que se quedaron a medias antes de" + CRLF
	cRet += "  decidir que se hace con ellos." + CRLF

Return cRet

// ---------------------------------------------------------------------
// De estos campos, los que existan en este ambiente.
// ---------------------------------------------------------------------
Static Function SelCpos()
	// Candidatos. Solo entran los que existan de verdad en este
	// ambiente: preguntar con FieldPos cuesta nada, y una consulta que
	// nombra un campo inexistente no trae menos datos, truena entera.
	//
	// Se prueban varios nombres para lo mismo porque el campo del numero
	// de recibo y el del importe no se llaman igual en todas las
	// versiones. Se corta en 4 columnas para que el renglon siga siendo
	// legible en la ventana.
	Local aWish := {"EL_NUM", "EL_NUMREC", "EL_RECIBO", ;
	                "EL_CLIENTE", "EL_LOJA", "EL_NOMCLI", ;
	                "EL_DATA", "EL_DTRECIB", "EL_EMISSAO", ;
	                "EL_VALREC", "EL_VALOR", "EL_TOTAL"}
	Local aRet  := {}
	Local nI    := 0

	For nI := 1 To Len(aWish)
		If Len(aRet) >= 4
			Exit
		EndIf
		If SEL->(FieldPos(aWish[nI])) > 0
			aAdd(aRet, aWish[nI])
		EndIf
	Next nI

Return aRet

// ---------------------------------------------------------------------
Static Function SelHay()

	If Select("SEL") == 0
		ChkFile("SEL")
	EndIf

Return Select("SEL") > 0

// ---------------------------------------------------------------------
// El nombre fisico, resuelto al correr.
//
// Escribir "SEL200" a mano amarra la rutina a un ambiente, y si el otro
// tuviera una tabla con ese nombre la leeria sin avisar que es la
// equivocada. RetSqlName lo resuelve; si no puede, el sufijo se saca de
// SF2, que siempre esta registrada.
// ---------------------------------------------------------------------
Static Function SelTab(cAlias)
	Local cAli := AllTrim(cAlias)
	Local cRet := ""
	Local cSuf := ""

	cRet := AllTrim(RetSqlName(cAli))

	If Empty(cRet) .Or. cRet == cAli
		cSuf := SubStr(AllTrim(RetSqlName("SF2")), 4)
		cRet := cAli + cSuf
	EndIf

Return cRet

// ---------------------------------------------------------------------
Static Function SelMues(cTitulo, cTexto)
	Local oDlg  := NIL
	Local oMem  := NIL
	Local cMemo := cTexto

	DEFINE MSDIALOG oDlg TITLE cTitulo FROM 0, 0 TO 560, 900 PIXEL

	@ 5, 5 GET oMem VAR cMemo MEMO SIZE 440, 255 OF oDlg PIXEL
	oMem:bWhen := {|| .F. }

	DEFINE SBUTTON FROM 262, 395 TYPE 1 ACTION oDlg:End() ENABLE OF oDlg

	ACTIVATE MSDIALOG oDlg CENTERED

Return
