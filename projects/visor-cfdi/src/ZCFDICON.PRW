#INCLUDE "PROTHEUS.CH"
#INCLUDE "TOPCONN.CH"

/*/{Protheus.doc} ZCFDICON
Conciliacion del visor de CFDI.

Responde la pregunta que trae el proyecto desde el principio:
QUE FACTURAS PPD SE COBRARON Y NUNCA SE LES TIMBRO EL COMPLEMENTO.

Hay dos formas de contestarla y las dos sirven, por distintas razones:

  1) SOLO XML
     Cruza los complementos (ZCP) contra las facturas PPD (ZCF).
     Es rapido y no depende de Protheus, pero solo ve lo que esta en
     la carpeta de XML. Si un XML nunca se guardo ahi, no existe.

  2) CONTRA PROTHEUS
     Cruza contra SF2 (facturas) y SEL (cobranza). Esa es la respuesta
     de verdad: el sistema sabe que se cobro aunque el XML no aparezca.

La 1 sirve de control de la 2. Si la 1 dice 20 y la 2 dice 60, la
diferencia son XML que no estan en la carpeta -- que ya es un hallazgo.

OJO: antes de cruzar contra Protheus hay que SABER como se llaman los
campos, no suponerlo. Por eso la opcion de sondeo. Ya nos costo tiempo
inventar nombres de campo (X6_DESCSPA, X3USO) que no existian.

@author Claude + Miguel Yasec
@since 09/2026
/*/
User Function ZCFDICON()
	Local nOpc := 0

	nOpc := Aviso("Conciliacion de CFDI", ;
		"Que factura PPD se cobro y nunca se timbro su complemento?" + CRLF + CRLF + ;
		"1. Solo XML  - rapido, ve solo la carpeta" + CRLF + ;
		"2. Protheus - la respuesta de verdad, contra SF2 y SEL" + CRLF + ;
		"3. Sondear  - que campos hay en SF2 y SEL", ;
		{"1. Solo XML", "2. Protheus", "3. Sondear"})

	Do Case
	Case nOpc == 1 ; ConXml()
	Case nOpc == 2 ; ConProt()
	Case nOpc == 3 ; ConSond()
	EndCase

Return
Static Function ConXml()
	Local aPag  := {}
	Local aFalt := {}
	Local cMsg  := ""
	Local nTot  := 0
	Local nPPD  := 0
	Local nSinU := 0
	Local nI    := 0
	Local nMont := 0

	If !ConAbre()
		Return
	EndIf

	// --- Que facturas quedaron pagadas segun los complementos -------
	// Un complemento (ZCP) dice a que UUID le esta pagando.
	ZCP->(DbGoTop())
	Do While !ZCP->(Eof())
		If !Empty(AllTrim(ZCP->ZCP_UUIDRE))
			If AScan(aPag, {|x| x[1] == Upper(AllTrim(ZCP->ZCP_UUIDRE)) }) == 0
				AAdd(aPag, {Upper(AllTrim(ZCP->ZCP_UUIDRE)), ZCP->ZCP_SALPAG})
			EndIf
		Else
			nSinU++
		EndIf
		ZCP->(DbSkip())
	EndDo

	// --- Que facturas PPD hay ---------------------------------------
	ZCF->(DbGoTop())
	Do While !ZCF->(Eof())
		nTot++

		// solo ingresos PPD vivos: un egreso o un cancelado no lleva REP
		If AllTrim(ZCF->ZCF_TIPCOM) == "I" .And. ;
		   AllTrim(ZCF->ZCF_METPAG) == "PPD" .And. ;
		   AllTrim(ZCF->ZCF_ESTSAT) != "C"

			nPPD++

			If AScan(aPag, {|x| x[1] == Upper(AllTrim(ZCF->ZCF_UUID)) }) == 0
				AAdd(aFalt, {AllTrim(ZCF->ZCF_SERIE), ;
				             AllTrim(ZCF->ZCF_FOLIO), ;
				             ConFec("ZCF", "ZCF_FECHA"), ;
				             ZCF->ZCF_TOTAL, ;
				             AllTrim(ZCF->ZCF_RECNOM), ;
				             AllTrim(ZCF->ZCF_UUID)})
				nMont += ZCF->ZCF_TOTAL
			EndIf
		EndIf

		ZCF->(DbSkip())
	EndDo

	// --- Reporte -----------------------------------------------------
	cMsg := "=== PPD SIN COMPLEMENTO (solo XML) ===" + CRLF + CRLF
	cMsg += "Comprobantes en el visor : " + cValToChar(nTot) + CRLF
	cMsg += "Facturas PPD vigentes    : " + cValToChar(nPPD) + CRLF
	cMsg += "Facturas ya pagadas      : " + cValToChar(nPPD - Len(aFalt)) + CRLF
	cMsg += "SIN COMPLEMENTO          : " + cValToChar(Len(aFalt)) + CRLF
	cMsg += "Monto involucrado        : " + ConNum(nMont) + CRLF + CRLF

	If nSinU > 0
		cMsg += "[!] " + cValToChar(nSinU) + " renglon(es) de complemento sin UUID" + CRLF
		cMsg += "    relacionado. Esos no se pudieron cruzar." + CRLF + CRLF
	EndIf

	cMsg += "OJO CON ESTE NUMERO: dice cuantas PPD no tienen complemento" + CRLF
	cMsg += "EN LA CARPETA. No dice cuantas se cobraron. Una PPD sin" + CRLF
	cMsg += "cobrar TAMPOCO lleva complemento, y esta bien asi." + CRLF
	cMsg += "Para saber cuales se cobraron hay que ir a Protheus." + CRLF + CRLF

	If Len(aFalt) == 0
		cMsg += "Ninguna PPD quedo sin complemento en esta muestra." + CRLF
	Else
		cMsg += "=== DETALLE ===" + CRLF + CRLF
		For nI := 1 To Len(aFalt)
			cMsg += PadR(aFalt[nI][1], 6) + " "
			cMsg += PadR(aFalt[nI][2], 18) + " "
			cMsg += PadR(aFalt[nI][3], 11) + " "
			cMsg += PadL(ConNum(aFalt[nI][4]), 14) + "  "
			cMsg += SubStr(aFalt[nI][5], 1, 35) + CRLF
			cMsg += "       " + aFalt[nI][6] + CRLF
		Next nI
	EndIf

	ConMues("Conciliacion - solo XML", cMsg)

Return

// ---------------------------------------------------------------------
// 2) Contra Protheus. Aqui esta la respuesta de verdad.
//
// TRES PREGUNTAS, EN ESTE ORDEN:
//
//   A) De las facturas de SF2, cuantas tienen su XML en el visor?
//      Mide que tan representativa es la carpeta.
//
//   B) Como se ve un cobro en SEL, en crudo?
//      Un recibo ocupa VARIOS renglones (EL_TIPO 'NF' el lado de la
//      factura, 'TF' la transferencia) que comparten un mismo UUID.
//      Por eso contar renglones NO es contar comprobantes. Ese error
//      ya duplico las cifras una vez en este proyecto. Se muestra la
//      muestra cruda para que se vea, no para que se crea.
//
//   C) Cuantos cobros NO tienen complemento timbrado?
//      Contado de las dos formas -- por renglon y por recibo -- para
//      que la diferencia quede a la vista y nadie repita el error.
// ---------------------------------------------------------------------
Static Function ConProt()
	Local cMsg := ""

	cMsg := "=== CONCILIACION CONTRA PROTHEUS ===" + CRLF + CRLF
	cMsg += "Solo lectura. No escribe nada." + CRLF + CRLF

	cMsg += ConSf2()
	cMsg += ConSf2S()
	cMsg += ConSelM()
	cMsg += ConSelC()
	cMsg += ConDif()
	cMsg += ConPrue()
	cMsg += ConGrup()

Return ConMues("Conciliacion contra Protheus", cMsg)

// ---------------------------------------------------------------------
// A) Facturas de SF2 contra los XML del visor.
// ---------------------------------------------------------------------
Static Function ConSf2()
	Local cRet := ""
	Local cAli := GetNextAlias()
	Local cQry := ""
	Local aUui := {}
	Local nTot := 0
	Local nCon := 0
	Local nSin := 0
	Local nVis := 0

	If !ConAbre()
		Return "  [!!] no se pudieron abrir las tablas del visor" + CRLF
	EndIf

	// Los UUID del visor, en memoria. NO por indice: ZCF es tabla
	// compartida y armar la llave con la sucursal daba cero coincidencias.
	ZCF->(DbGoTop())
	Do While !ZCF->(Eof())
		AAdd(aUui, Upper(AllTrim(ZCF->ZCF_UUID)))
		ZCF->(DbSkip())
	EndDo

	cQry := "SELECT F2_SERIE, F2_DOC, F2_UUID "
	cQry += "  FROM " + RetSqlName("SF2") + " "
	cQry += " WHERE D_E_L_E_T_ = ' ' "

	TCQuery cQry NEW ALIAS (cAli)

	Do While !(cAli)->(Eof())
		nTot++
		If Empty(AllTrim((cAli)->F2_UUID))
			nSin++
		Else
			nCon++
			If AScan(aUui, Upper(AllTrim((cAli)->F2_UUID))) > 0
				nVis++
			EndIf
		EndIf
		(cAli)->(DbSkip())
	EndDo

	(cAli)->(DbCloseArea())

	cRet := "== A) FACTURAS DE SF2 CONTRA EL VISOR ==" + CRLF
	cRet += "  Facturas en SF2        : " + cValToChar(nTot) + CRLF
	cRet += "  Con folio fiscal       : " + cValToChar(nCon) + CRLF
	cRet += "  SIN folio fiscal       : " + cValToChar(nSin) + CRLF
	cRet += "  Con su XML en el visor : " + cValToChar(nVis) + CRLF
	cRet += "  Timbradas SIN XML aqui : " + cValToChar(nCon - nVis) + CRLF + CRLF

	cRet += "  Las que no tienen XML aqui NO estan mal: estan timbradas" + CRLF
	cRet += "  en el SAT. Lo que falta es el archivo en la carpeta." + CRLF
	cRet += "  Eso dice que tan completa es la muestra del visor." + CRLF + CRLF

Return cRet

// ---------------------------------------------------------------------
// A-bis) Las facturas SIN folio fiscal, una por una.
//
// Una factura sin UUID no existe ante el SAT. Pero antes de alarmarse
// hay que ver QUE son: puede que ni siquiera sean facturas de venta.
// En SF2 conviven documentos de varias especies y tipos, y no todos se
// timbran. Por eso se muestran la especie, el tipo y la fecha: para
// distinguir "falta timbrar" de "este documento no se timbra".
// ---------------------------------------------------------------------
Static Function ConSf2S()
	Local cRet := ""
	Local cAli := GetNextAlias()
	Local cQry := ""
	Local nN   := 0
	Local nMon := 0

	cQry := "SELECT F2_SERIE, F2_DOC, F2_EMISSAO, F2_CLIENTE, F2_LOJA, "
	cQry += "       F2_VALBRUT, F2_TIPO, F2_ESPECIE "
	cQry += "  FROM " + RetSqlName("SF2") + " "
	cQry += " WHERE D_E_L_E_T_ = ' ' "
	cQry += "   AND (F2_UUID IS NULL OR TRIM(F2_UUID) IS NULL) "
	cQry += " ORDER BY F2_EMISSAO, F2_SERIE, F2_DOC "

	TCQuery cQry NEW ALIAS (cAli)

	cRet := "== A-bis) FACTURAS SIN FOLIO FISCAL ==" + CRLF
	cRet += "  serie-folio / fecha / cliente / especie-tipo / valor" + CRLF + CRLF

	Do While !(cAli)->(Eof())
		nN++
		nMon += (cAli)->F2_VALBRUT

		cRet += "    " + PadR(AllTrim((cAli)->F2_SERIE) + "-" + ;
		        AllTrim((cAli)->F2_DOC), 20)
		cRet += PadR(ConFSql((cAli)->F2_EMISSAO), 11)
		cRet += PadR(AllTrim((cAli)->F2_CLIENTE) + "/" + ;
		        AllTrim((cAli)->F2_LOJA), 10)
		cRet += PadR(AllTrim((cAli)->F2_ESPECIE) + " " + ;
		        AllTrim((cAli)->F2_TIPO), 8)
		cRet += PadL(ConNum((cAli)->F2_VALBRUT), 14)
		cRet += CRLF

		(cAli)->(DbSkip())
	EndDo

	(cAli)->(DbCloseArea())

	cRet += CRLF + "  Son " + cValToChar(nN) + ", por " + ConNum(nMon) + CRLF + CRLF
	cRet += "  COMO LEER ESTO: si la especie es de venta y la fecha ya" + CRLF
	cRet += "  paso, falta timbrar. Si es otra especie, revisar si ese" + CRLF
	cRet += "  documento se timbra siquiera antes de reportarlo." + CRLF + CRLF

Return cRet

// ---------------------------------------------------------------------
// Una fecha que viene de una query puede llegar como fecha o como texto.
// ---------------------------------------------------------------------
Static Function ConFSql(xVal)
	Local cRet := ""

	Do Case
	Case ValType(xVal) == "D"
		cRet := IIf(Empty(xVal), "", DToC(xVal))
	Case ValType(xVal) == "C" .And. Len(AllTrim(xVal)) == 8
		cRet := DToC(SToD(AllTrim(xVal)))
	Otherwise
		cRet := ""
	EndCase

Return cRet

// ---------------------------------------------------------------------
// B) Como se ve un cobro en SEL, en crudo.
// ---------------------------------------------------------------------
Static Function ConSelM()
	Local cRet := ""
	Local cAli := GetNextAlias()
	Local cQry := ""
	Local cRec := ""
	Local nN   := 0

	cQry := "SELECT EL_RECIBO, EL_TIPO, EL_PREFIXO, EL_NUMERO, "
	cQry += "       EL_UUID, EL_VALOR "
	cQry += "  FROM " + RetSqlName("SEL") + " "
	cQry += " WHERE D_E_L_E_T_ = ' ' "
	cQry += " ORDER BY EL_RECIBO, EL_TIPO "

	TCQuery cQry NEW ALIAS (cAli)

	cRet := "== B) COMO SE VE UN COBRO EN SEL ==" + CRLF
	cRet += "  recibo / tipo / serie-folio / uuid / valor" + CRLF + CRLF

	Do While !(cAli)->(Eof()) .And. nN < 14

		If AllTrim((cAli)->EL_RECIBO) != cRec
			cRec := AllTrim((cAli)->EL_RECIBO)
			cRet += "  -- recibo " + cRec + CRLF
		EndIf

		cRet += "     " + PadR(AllTrim((cAli)->EL_TIPO), 3)
		cRet += PadR(AllTrim((cAli)->EL_PREFIXO) + "-" + AllTrim((cAli)->EL_NUMERO), 20)
		cRet += PadR(IIf(Empty(AllTrim((cAli)->EL_UUID)), "(sin uuid)", ;
		              SubStr(AllTrim((cAli)->EL_UUID), 1, 13) + ".."), 17)
		cRet += PadL(ConNum((cAli)->EL_VALOR), 13)
		cRet += CRLF

		nN++
		(cAli)->(DbSkip())
	EndDo

	(cAli)->(DbCloseArea())

	cRet += CRLF + "  Si un mismo recibo sale en varios renglones, contar" + CRLF
	cRet += "  renglones da un numero INFLADO. Se cuenta por recibo." + CRLF + CRLF

Return cRet

// ---------------------------------------------------------------------
// C) Cobros sin complemento timbrado. Contado de las dos formas.
// ---------------------------------------------------------------------
Static Function ConSelC()
	Local cRet := ""
	Local cAli := GetNextAlias()
	Local cQry := ""
	Local aSin := {}
	Local nRen := 0
	Local nTot := 0
	Local nRTo := 0
	Local nI   := 0
	Local nMon := 0
	Local cRec := ""

	cQry := "SELECT EL_RECIBO, EL_PREFIXO, EL_NUMERO, EL_UUID, "
	cQry += "       EL_VALOR, EL_EMISSAO, EL_CLIENTE "
	cQry += "  FROM " + RetSqlName("SEL") + " "
	cQry += " WHERE D_E_L_E_T_ = ' ' "
	cQry += "   AND EL_TIPO = 'NF' "
	cQry += " ORDER BY EL_RECIBO "

	TCQuery cQry NEW ALIAS (cAli)

	Do While !(cAli)->(Eof())
		nRTo++

		If AllTrim((cAli)->EL_RECIBO) != cRec
			cRec := AllTrim((cAli)->EL_RECIBO)
			nTot++
		EndIf

		If Empty(AllTrim((cAli)->EL_UUID))
			nRen++
			If AScan(aSin, {|x| x[1] == AllTrim((cAli)->EL_RECIBO) }) == 0
				AAdd(aSin, {AllTrim((cAli)->EL_RECIBO), ;
				            AllTrim((cAli)->EL_PREFIXO), ;
				            AllTrim((cAli)->EL_NUMERO), ;
				            (cAli)->EL_VALOR, ;
				            AllTrim((cAli)->EL_CLIENTE)})
				nMon += (cAli)->EL_VALOR
			EndIf
		EndIf

		(cAli)->(DbSkip())
	EndDo

	(cAli)->(DbCloseArea())

	cRet := "== C) COBROS SIN COMPLEMENTO TIMBRADO ==" + CRLF + CRLF
	cRet += "  Renglones de cobro (EL_TIPO='NF') : " + cValToChar(nRTo) + CRLF
	cRet += "  Recibos distintos                 : " + cValToChar(nTot) + CRLF + CRLF
	cRet += "  SIN UUID, contado por renglon     : " + cValToChar(nRen) + CRLF
	cRet += "  SIN UUID, contado por RECIBO      : " + cValToChar(Len(aSin)) + CRLF
	cRet += "  Monto involucrado                 : " + ConNum(nMon) + CRLF + CRLF

	If nRen != Len(aSin)
		cRet += "  [!] Los dos numeros NO son iguales. El bueno es el de" + CRLF
		cRet += "      RECIBO. El de renglon esta inflado " + ;
		        AllTrim(Transform(nRen / Max(Len(aSin), 1), "@E 99.99")) + " veces." + CRLF + CRLF
	EndIf

	If Len(aSin) == 0
		cRet += "  Ningun cobro quedo sin complemento." + CRLF
		Return cRet
	EndIf

	cRet += "  === RECIBOS SIN COMPLEMENTO ===" + CRLF
	cRet += "  recibo / factura que paga / cliente / valor" + CRLF + CRLF

	For nI := 1 To Min(Len(aSin), 60)
		cRet += "    " + PadR(aSin[nI][1], 10)
		cRet += PadR(aSin[nI][2] + "-" + aSin[nI][3], 20)
		cRet += PadR(aSin[nI][5], 8)
		cRet += PadL(ConNum(aSin[nI][4]), 14)
		cRet += CRLF
	Next nI

	If Len(aSin) > 60
		cRet += CRLF + "    ... y " + cValToChar(Len(aSin) - 60) + " mas." + CRLF
	EndIf

Return cRet

// ---------------------------------------------------------------------
// E) Que distingue a una factura serie B que fallo de una que si timbro.
//
// El dato por serie mato la hipotesis facil: la serie B SI timbra, 25 de
// 30. No esta apagada. Falla una de cada seis, repartido en el tiempo.
//
// Cuando la causa no esta en la configuracion, esta en el dato. Asi que
// en vez de adivinar que campo mirar, se comparan DOS facturas de la
// misma serie -- una que fallo y una que si -- y se listan solo los
// campos donde diferen. El que sobra en esa lista es el sospechoso.
//
// Cinco casos no dan para estadistica. Dan para encontrar el patron.
// ---------------------------------------------------------------------
Static Function ConDif()
	Local cRet := ""
	Local nRMal := 0
	Local nRBien := 0
	Local nN   := 0
	Local cCpo := ""
	Local xMal := NIL
	Local xBien := NIL
	Local cMal := ""
	Local cBien := ""
	Local nDif := 0

	If Select("SF2") == 0
		ChkFile("SF2")
	EndIf
	If Select("SF2") == 0
		Return "  [!!] no se pudo abrir SF2" + CRLF
	EndIf

	cRet := "== E) SERIE B: LA QUE FALLO CONTRA LA QUE SI TIMBRO ==" + CRLF + CRLF

	// --- Buscar una de cada una, con importe real ---------------------
	SF2->(DbGoTop())
	Do While !SF2->(Eof())
		If AllTrim(SF2->F2_SERIE) == "B" .And. SF2->F2_VALBRUT > 0
			If Empty(AllTrim(SF2->F2_UUID)) .And. nRMal == 0
				nRMal := SF2->(RecNo())
			ElseIf !Empty(AllTrim(SF2->F2_UUID)) .And. nRBien == 0
				nRBien := SF2->(RecNo())
			EndIf
		EndIf
		If nRMal > 0 .And. nRBien > 0
			Exit
		EndIf
		SF2->(DbSkip())
	EndDo

	If nRMal == 0 .Or. nRBien == 0
		Return cRet + "  No se encontro una pareja para comparar." + CRLF + CRLF
	EndIf

	SF2->(DbGoTo(nRMal))
	cRet += "  SIN TIMBRAR: " + AllTrim(SF2->F2_SERIE) + "-" + AllTrim(SF2->F2_DOC)
	cRet += "   " + ConFSql(SF2->F2_EMISSAO)
	cRet += "   " + ConNum(SF2->F2_VALBRUT) + CRLF

	SF2->(DbGoTo(nRBien))
	cRet += "  TIMBRADA   : " + AllTrim(SF2->F2_SERIE) + "-" + AllTrim(SF2->F2_DOC)
	cRet += "   " + ConFSql(SF2->F2_EMISSAO)
	cRet += "   " + ConNum(SF2->F2_VALBRUT) + CRLF + CRLF

	cRet += "  CAMPOS DONDE DIFIEREN:" + CRLF
	cRet += "    campo          sin timbrar | timbrada" + CRLF + CRLF

	// --- Comparar campo por campo -------------------------------------
	For nN := 1 To SF2->(FCount())
		cCpo := AllTrim(SF2->(FieldName(nN)))

		// Estos SIEMPRE difieren y no dicen nada: son la identidad del
		// documento o el resultado del timbrado, no su causa.
		If cCpo $ "F2_DOC/F2_UUID/F2_FECTIMB/F2_TIMBRE/F2_EMISSAO/" + ;
		          "F2_DTDIGIT/F2_HORA/F2_NUMRDM/F2_DATENTR/F2_SEQENT"
			Loop
		EndIf

		SF2->(DbGoTo(nRMal))
		xMal := SF2->(FieldGet(nN))

		SF2->(DbGoTo(nRBien))
		xBien := SF2->(FieldGet(nN))

		cMal  := ConVal2(xMal)
		cBien := ConVal2(xBien)

		If cMal == cBien
			Loop
		EndIf

		// Si los dos estan vacios de formas distintas, no es diferencia.
		If Empty(cMal) .And. Empty(cBien)
			Loop
		EndIf

		nDif++
		If nDif > 45
			Loop
		EndIf

		cRet += "    " + PadR(cCpo, 14)
		cRet += PadR(SubStr(cMal, 1, 16), 17) + "| "
		cRet += SubStr(cBien, 1, 16)
		cRet += CRLF
	Next nN

	cRet += CRLF + "  Son " + cValToChar(nDif) + " campos distintos." + CRLF
	If nDif > 45
		cRet += "  (se muestran los primeros 45)" + CRLF
	EndIf

	cRet += CRLF + "  COMO LEER ESTO: casi todo va a ser ruido -- importes," + CRLF
	cRet += "  productos, consecutivos. Busca lo que hable de COMO se hizo" + CRLF
	cRet += "  la factura: cliente, tipo de operacion, condicion de pago," + CRLF
	cRet += "  vendedor, quien la capturo. Ahi esta el patron, si lo hay." + CRLF

Return cRet

// ---------------------------------------------------------------------
// F) La prueba: el patron de la seccion E, aguanta en las 281?
//
// Comparar DOS facturas dio 18 campos distintos. Dos de ellos parecian
// explicar algo -- F2_PREFIXO y F2_DTLANC vacia. Pero dos documentos
// difieren en muchas cosas por pura casualidad, y quedarse con el campo
// que nos gusto es armar la conclusion antes que la evidencia.
//
// Asi que se prueba contra TODAS. Si las sin timbrar estan sin lanzar y
// las timbradas estan lanzadas, la causa es esa. Si no, la pista era
// ruido y hay que tirarla.
// ---------------------------------------------------------------------
Static Function ConPrue()
	Local cRet := ""
	Local cAli := GetNextAlias()
	Local cQry := ""
	Local nPct := 0

	// --- Prueba 1: lanzada o no, contra timbrada o no ------------------
	cQry := "SELECT CASE WHEN F2_DTLANC IS NULL OR TRIM(F2_DTLANC) IS NULL "
	cQry += "            THEN 'SIN LANZAR' ELSE 'LANZADA' END AS ESTADO, "
	cQry += "       COUNT(*) AS TOTAL, "
	cQry += "       SUM(CASE WHEN TRIM(F2_UUID) IS NULL THEN 1 ELSE 0 END) AS SINUUID "
	cQry += "  FROM " + RetSqlName("SF2") + " "
	cQry += " WHERE D_E_L_E_T_ = ' ' "
	cQry += " GROUP BY CASE WHEN F2_DTLANC IS NULL OR TRIM(F2_DTLANC) IS NULL "
	cQry += "               THEN 'SIN LANZAR' ELSE 'LANZADA' END "

	TCQuery cQry NEW ALIAS (cAli)

	cRet := "== F) LA PRUEBA: AGUANTA EL PATRON? ==" + CRLF + CRLF
	cRet += "  1) LANZADA (F2_DTLANC) contra TIMBRADA" + CRLF
	cRet += "     estado / facturas / sin timbrar / %" + CRLF + CRLF

	Do While !(cAli)->(Eof())
		nPct := IIf((cAli)->TOTAL > 0, ((cAli)->SINUUID / (cAli)->TOTAL) * 100, 0)

		cRet += "     " + PadR(AllTrim((cAli)->ESTADO), 12)
		cRet += PadL(cValToChar((cAli)->TOTAL), 6)
		cRet += PadL(cValToChar((cAli)->SINUUID), 8)
		cRet += PadL(AllTrim(Transform(nPct, "@E 999.9")) + "%", 9)
		cRet += CRLF

		(cAli)->(DbSkip())
	EndDo

	(cAli)->(DbCloseArea())

	cRet += CRLF + "     SI ESTO EXPLICA TODO, las sin lanzar salen en 100%" + CRLF
	cRet += "     y las lanzadas en 0%. Cualquier otra cosa quiere decir" + CRLF
	cRet += "     que el lanzamiento no es la causa, o no es la unica." + CRLF + CRLF

	// --- Prueba 2: prefijo fiscal --------------------------------------
	cAli := GetNextAlias()

	cQry := "SELECT F2_PREFIXO, "
	cQry += "       COUNT(*) AS TOTAL, "
	cQry += "       SUM(CASE WHEN TRIM(F2_UUID) IS NULL THEN 1 ELSE 0 END) AS SINUUID "
	cQry += "  FROM " + RetSqlName("SF2") + " "
	cQry += " WHERE D_E_L_E_T_ = ' ' "
	cQry += " GROUP BY F2_PREFIXO "
	cQry += " ORDER BY F2_PREFIXO "

	TCQuery cQry NEW ALIAS (cAli)

	cRet += "  2) PREFIJO FISCAL (F2_PREFIXO) contra TIMBRADA" + CRLF
	cRet += "     prefijo / facturas / sin timbrar / %" + CRLF + CRLF

	Do While !(cAli)->(Eof())
		nPct := IIf((cAli)->TOTAL > 0, ((cAli)->SINUUID / (cAli)->TOTAL) * 100, 0)

		cRet += "     " + PadR(IIf(Empty(AllTrim((cAli)->F2_PREFIXO)), ;
		                          "(vacio)", AllTrim((cAli)->F2_PREFIXO)), 12)
		cRet += PadL(cValToChar((cAli)->TOTAL), 6)
		cRet += PadL(cValToChar((cAli)->SINUUID), 8)
		cRet += PadL(AllTrim(Transform(nPct, "@E 999.9")) + "%", 9)
		cRet += CRLF

		(cAli)->(DbSkip())
	EndDo

	(cAli)->(DbCloseArea())

	cRet += CRLF + "     Si un prefijo falla parejo y los demas no, el" + CRLF
	cRet += "     problema es como esta dado de alta ESE prefijo." + CRLF + CRLF

Return cRet

// ---------------------------------------------------------------------
// G) Dentro de un prefijo de ejemplo: las que fallaron contra las que si timbraron.
//
// Un prefijo puede fallar siempre, nunca, o solo a veces. El que
// falla a veces es el que hay que comparar por grupos.
//
// Comparar dos documentos sueltos ya nos mintio una vez -- la fecha de
// lanzamiento parecia explicarlo y no explicaba nada. Asi que ahora no
// se comparan dos: se comparan los DOS GRUPOS enteros, y solo se reporta
// un campo cuando SEPARA LIMPIO -- o sea, cuando ningun valor del grupo
// que fallo aparece en el grupo que timbro.
//
// Un campo que separa limpio en 5 contra 18 puede seguir siendo
// casualidad, pero ya es una casualidad cara. Un campo que no separa
// queda descartado sin discusion.
// ---------------------------------------------------------------------
Static Function ConGrup()
	Local cRet  := ""
	Local aMal  := {}
	Local aBien := {}
	Local aVMal := {}
	Local aVBie := {}
	Local cCpo  := ""
	Local cVal  := ""
	Local nN    := 0
	Local nI    := 0
	Local nSep  := 0
	Local lSep  := .F.

	If Select("SF2") == 0
		ChkFile("SF2")
	EndIf
	If Select("SF2") == 0
		Return "  [!!] no se pudo abrir SF2" + CRLF
	EndIf

	// --- Armar los dos grupos -----------------------------------------
	SF2->(DbGoTop())
	Do While !SF2->(Eof())
		If AllTrim(SF2->F2_PREFIXO) == "B"
			If Empty(AllTrim(SF2->F2_UUID))
				AAdd(aMal, SF2->(RecNo()))
			Else
				AAdd(aBien, SF2->(RecNo()))
			EndIf
		EndIf
		SF2->(DbSkip())
	EndDo

	cRet := "== G) PREFIJO DE EJEMPLO: LAS QUE FALLARON CONTRA LAS QUE NO ==" + CRLF + CRLF
	cRet += "  Sin timbrar : " + cValToChar(Len(aMal)) + CRLF
	cRet += "  Timbradas   : " + cValToChar(Len(aBien)) + CRLF + CRLF

	If Len(aMal) == 0 .Or. Len(aBien) == 0
		Return cRet + "  Falta uno de los dos grupos. No hay que comparar." + CRLF
	EndIf

	cRet += "  CAMPOS QUE SEPARAN LIMPIO:" + CRLF
	cRet += "  (ningun valor de las que fallaron aparece en las que si)" + CRLF + CRLF

	For nN := 1 To SF2->(FCount())
		cCpo := AllTrim(SF2->(FieldName(nN)))

		// Resultado del timbrado o identidad del documento: no explican.
		If cCpo $ "F2_UUID/F2_FECTIMB/F2_TIMBRE/F2_MSUIDT/F2_DOC/F2_DUPL/" + ;
		          "F2_USERLGA/F2_USERLGI/F2_CFDVLTR"
			Loop
		EndIf

		aVMal := {}
		aVBie := {}

		For nI := 1 To Len(aMal)
			SF2->(DbGoTo(aMal[nI]))
			cVal := ConVal2(SF2->(FieldGet(nN)))
			If AScan(aVMal, cVal) == 0
				AAdd(aVMal, cVal)
			EndIf
		Next nI

		For nI := 1 To Len(aBien)
			SF2->(DbGoTo(aBien[nI]))
			cVal := ConVal2(SF2->(FieldGet(nN)))
			If AScan(aVBie, cVal) == 0
				AAdd(aVBie, cVal)
			EndIf
		Next nI

		// Separa limpio? Ningun valor en comun.
		lSep := .T.
		For nI := 1 To Len(aVMal)
			If AScan(aVBie, aVMal[nI]) > 0
				lSep := .F.
				Exit
			EndIf
		Next nI

		If !lSep
			Loop
		EndIf

		// Un campo que trae un valor distinto en cada renglon separa
		// limpio por construccion y no dice nada. Solo interesa cuando
		// el grupo que fallo se agrupa en pocos valores.
		If Len(aVMal) > 2
			Loop
		EndIf

		nSep++

		cRet += "    " + PadR(cCpo, 14) + CRLF
		cRet += "      fallaron: " + SubStr(ConLis(aVMal), 1, 55) + CRLF
		cRet += "      timbradas: " + SubStr(ConLis(aVBie), 1, 55) + CRLF + CRLF

	Next nN

	If nSep == 0
		cRet += "    NINGUNO." + CRLF + CRLF
		cRet += "    Eso tambien es un resultado: las que fallaron no se" + CRLF
		cRet += "    distinguen por el contenido de la factura. Entonces la" + CRLF
		cRet += "    causa no esta en SF2 -- hay que buscarla en el proceso" + CRLF
		cRet += "    de timbrado, no en el documento." + CRLF
	Else
		cRet += "    Son " + cValToChar(nSep) + " campos que separan limpio." + CRLF
		cRet += "    Con 5 contra " + cValToChar(Len(aBien)) + " todavia puede ser" + CRLF
		cRet += "    casualidad. Se confirma abriendo esas facturas y" + CRLF
		cRet += "    viendo si el campo tiene sentido como causa." + CRLF
	EndIf

Return cRet + CRLF

// ---------------------------------------------------------------------
Static Function ConLis(aVal)
	Local cRet := ""
	Local nI   := 0

	For nI := 1 To Len(aVal)
		cRet += IIf(nI > 1, ", ", "")
		cRet += IIf(Empty(aVal[nI]), "(vacio)", aVal[nI])
	Next nI

Return cRet

// ---------------------------------------------------------------------
// Valor como texto, para poder compararlo sea del tipo que sea.
// ---------------------------------------------------------------------
Static Function ConVal2(xVal)
	Local cRet := ""

	Do Case
	Case ValType(xVal) == "C" ; cRet := AllTrim(xVal)
	Case ValType(xVal) == "N" ; cRet := AllTrim(Str(xVal))
	Case ValType(xVal) == "D" ; cRet := IIf(Empty(xVal), "", DToC(xVal))
	Case ValType(xVal) == "L" ; cRet := IIf(xVal, "V", "F")
	EndCase

Return cRet

// ---------------------------------------------------------------------
// 3) Sondeo: que campos tienen SF2 y SEL en ESTE ambiente.
//
// No se cruza nada todavia. Primero se ve con que se cuenta.
// ---------------------------------------------------------------------
Static Function ConSond()
	Local cMsg := ""

	cMsg := "=== QUE HAY EN SF2 Y SEL ===" + CRLF + CRLF
	cMsg += "Esto no cruza nada. Solo lista los campos, para escribir" + CRLF
	cMsg += "el cruce sobre nombres reales y no sobre suposiciones." + CRLF + CRLF

	cMsg += ConSer()
	cMsg += ConCpo("SF2", "Facturas de salida")
	cMsg += ConCpo("SEL", "Recibos de cobranza")

Return ConMues("Sondeo SF2 / SEL", cMsg)

// ---------------------------------------------------------------------
// Timbrado POR SERIE.
//
// De las 12 facturas sin folio fiscal, las 5 con importe real resultaron
// ser todas serie B. Eso puede ser casualidad de una muestra chica, o
// puede ser que la serie B no este configurada para timbrar. La forma de
// saberlo no es mirar esas 5, es mirar TODAS: si la serie B falla en
// proporcion y las demas no, el problema es la serie, no las facturas.
// ---------------------------------------------------------------------
Static Function ConSer()
	Local cRet := ""
	Local cAli := GetNextAlias()
	Local cQry := ""
	Local nPct := 0

	cQry := "SELECT F2_SERIE, "
	cQry += "       COUNT(*) AS TOTAL, "
	cQry += "       SUM(CASE WHEN TRIM(F2_UUID) IS NULL THEN 1 ELSE 0 END) AS SINUUID "
	cQry += "  FROM " + RetSqlName("SF2") + " "
	cQry += " WHERE D_E_L_E_T_ = ' ' "
	cQry += " GROUP BY F2_SERIE "
	cQry += " ORDER BY F2_SERIE "

	TCQuery cQry NEW ALIAS (cAli)

	cRet := "== TIMBRADO POR SERIE ==" + CRLF
	cRet += "  serie / facturas / sin folio fiscal / % sin timbrar" + CRLF + CRLF

	Do While !(cAli)->(Eof())

		nPct := IIf((cAli)->TOTAL > 0, ;
		            ((cAli)->SINUUID / (cAli)->TOTAL) * 100, 0)

		cRet += "    " + PadR(AllTrim((cAli)->F2_SERIE), 8)
		cRet += PadL(cValToChar((cAli)->TOTAL), 6)
		cRet += PadL(cValToChar((cAli)->SINUUID), 8)
		cRet += PadL(AllTrim(Transform(nPct, "@E 999.9")) + "%", 9)

		If nPct >= 50 .And. (cAli)->TOTAL > 1
			cRet += "   <-- revisar esta serie"
		EndIf

		cRet += CRLF
		(cAli)->(DbSkip())
	EndDo

	(cAli)->(DbCloseArea())

	cRet += CRLF + "  Una serie que falla en proporcion apunta a la" + CRLF
	cRet += "  configuracion de la serie. Una que falla en un caso" + CRLF
	cRet += "  suelto apunta a esa factura." + CRLF + CRLF

	cRet += ConSx5()

Return cRet

// ---------------------------------------------------------------------
// Como estan dadas de alta las series en el diccionario (SX5 tabla 01).
//
// El nombre del campo de descripcion cambia entre localizaciones
// (X5_DESCRI / X5_DESCSPA / X5_DESCENG). Se busca cual existe en vez de
// suponerlo -- ya perdimos tiempo con X6_DESCSPA y X3USO.
// ---------------------------------------------------------------------
Static Function ConSx5()
	Local cRet := ""
	Local nN   := 0

	cRet := "  == SERIES DADAS DE ALTA (SX5 tabla 01) ==" + CRLF

	If Select("SX5") == 0
		ChkFile("SX5")
	EndIf
	If Select("SX5") == 0
		Return cRet + "    [!!] no se pudo abrir SX5" + CRLF + CRLF
	EndIf

	SX5->(DbGoTop())
	Do While !SX5->(Eof()) .And. nN < 40
		If AllTrim(SX5->X5_TABELA) == "01"
			nN++
			cRet += "    " + PadR(AllTrim(SX5->X5_CHAVE), 8)
			cRet += ConDes("SX5")
			cRet += CRLF
		EndIf
		SX5->(DbSkip())
	EndDo

	If nN == 0
		cRet += "    (no hay renglones en la tabla 01)" + CRLF
	EndIf

Return cRet + CRLF

// ---------------------------------------------------------------------
// Devuelve la descripcion, se llame como se llame en este ambiente.
// ---------------------------------------------------------------------
Static Function ConDes(cAli)
	Local aCpo := {"X5_DESCRI", "X5_DESCSPA", "X5_DESCENG", "X5_DESCPOR"}
	Local nI   := 0
	Local nPos := 0

	For nI := 1 To Len(aCpo)
		nPos := (cAli)->(FieldPos(aCpo[nI]))
		If nPos > 0 .And. !Empty(AllTrim((cAli)->(FieldGet(nPos))))
			Return AllTrim((cAli)->(FieldGet(nPos)))
		EndIf
	Next nI

Return "(sin descripcion)"

// ---------------------------------------------------------------------
// Lista los campos de una tabla, marcando los que nos interesan.
// ---------------------------------------------------------------------
Static Function ConCpo(cAli, cDes)
	Local cRet := ""
	Local cCpo := ""
	Local cFis := ""
	Local nN   := 0
	Local nLin := 0
	Local lOjo := .F.

	cRet := "== " + cAli + " - " + cDes + " ==" + CRLF

	If Select(cAli) == 0
		ChkFile(cAli)
	EndIf
	If Select(cAli) == 0
		Return cRet + "  [!!] no se pudo abrir" + CRLF + CRLF
	EndIf

	cFis := RetSqlName(cAli)
	cRet += "  tabla fisica: " + cFis + CRLF
	cRet += "  registros   : " + cValToChar((cAli)->(LastRec())) + CRLF + CRLF

	// Nos paramos en un registro para poder leer el tipo de cada campo.
	// OJO: FieldType() NO existe en ADVPL. El tipo se saca del valor.
	(cAli)->(DbGoTop())

	// Primero los que buscamos: timbre, folio, fecha, tipo, valor.
	cRet += "  CAMPOS QUE NOS INTERESAN:" + CRLF
	For nN := 1 To (cAli)->(FCount())
		cCpo := AllTrim((cAli)->(FieldName(nN)))
		lOjo := ("UUID" $ cCpo) .Or. ("TIMB" $ cCpo) .Or. ("CFDI" $ cCpo) ;
		        .Or. ("SERIE" $ cCpo) .Or. ("DOC" $ cCpo) .Or. ("EMISS" $ cCpo) ;
		        .Or. ("NUMERO" $ cCpo) .Or. ("PREFIX" $ cCpo) .Or. ("TIPO" $ cCpo) ;
		        .Or. ("VALBR" $ cCpo) .Or. ("VALOR" $ cCpo) .Or. ("CLIENT" $ cCpo) ;
		        .Or. ("VENCR" $ cCpo) .Or. ("BAIXA" $ cCpo) .Or. ("SALDO" $ cCpo)

		If lOjo
			cRet += "    " + PadR(cCpo, 14)
			cRet += PadR(ValType((cAli)->(FieldGet(nN))), 2)
			cRet += "  " + ConVal((cAli)->(FieldGet(nN)))
			cRet += CRLF
		EndIf
	Next nN

	cRet += CRLF + "  TODOS (" + cValToChar((cAli)->(FCount())) + "):" + CRLF + "    "
	For nN := 1 To (cAli)->(FCount())
		cRet += PadR(AllTrim((cAli)->(FieldName(nN))), 14)
		nLin++
		If nLin >= 5
			cRet += CRLF + "    "
			nLin := 0
		EndIf
	Next nN

Return cRet + CRLF + CRLF

// ---------------------------------------------------------------------
// Muestra un valor de ejemplo, sea del tipo que sea. Ver un dato real
// dice mas que el tipo: asi se sabe si un campo trae UUID, ceros a la
// izquierda, o esta vacio en todos lados.
// ---------------------------------------------------------------------
Static Function ConVal(xVal)
	Local cRet := ""

	Do Case
	Case ValType(xVal) == "C" ; cRet := AllTrim(xVal)
	Case ValType(xVal) == "N" ; cRet := AllTrim(Str(xVal))
	Case ValType(xVal) == "D" ; cRet := IIf(Empty(xVal), "", DToC(xVal))
	Case ValType(xVal) == "L" ; cRet := IIf(xVal, "verdadero", "falso")
	Otherwise                 ; cRet := "?"
	EndCase

	If Empty(cRet)
		Return "(vacio en el 1er registro)"
	EndIf

Return "ej: " + SubStr(cRet, 1, 40)

// ---------------------------------------------------------------------
// Abre las tablas del visor.
// ---------------------------------------------------------------------
Static Function ConAbre()
	Local aArq := {"ZCF", "ZCP"}
	Local nI   := 0

	For nI := 1 To Len(aArq)
		If Select(aArq[nI]) == 0
			ChkFile(aArq[nI])
		EndIf
		If Select(aArq[nI]) == 0
			MsgStop("No se pudo abrir " + aArq[nI] + "." + CRLF + CRLF + ;
				"Corre primero Construir - Crear tablas, y sal y vuelve" + CRLF + ;
				"a entrar al modulo para que recargue el diccionario.", ;
				"ZCFDICON")
			Return .F.
		EndIf
	Next nI

	If ZCF->(LastRec()) == 0
		MsgInfo("No hay comprobantes cargados." + CRLF + CRLF + ;
			"Corre primero Construir - Importar XML.", "ZCFDICON")
		Return .F.
	EndIf

Return .T.

// ---------------------------------------------------------------------
// Una fecha puede venir como fecha o como texto AAAAMMDD.
// ---------------------------------------------------------------------
Static Function ConFec(cAlias, cCampo)
	Local nPos := (cAlias)->(FieldPos(cCampo))
	Local xVal := NIL
	Local cRet := ""

	If nPos == 0
		Return ""
	EndIf

	xVal := (cAlias)->(FieldGet(nPos))

	Do Case
	Case ValType(xVal) == "D"
		cRet := IIf(Empty(xVal), "", DToC(xVal))
	Case ValType(xVal) == "C" .And. Len(AllTrim(xVal)) == 8
		cRet := DToC(SToD(AllTrim(xVal)))
	EndCase

Return cRet

// ---------------------------------------------------------------------
Static Function ConNum(nVal)
Return AllTrim(Transform(nVal, "@E 999,999,999.99"))

// ---------------------------------------------------------------------
// Ventana de solo lectura con texto desplazable.
//
// OJO: no usar cVer como nombre de variable, choca con el framework.
// ---------------------------------------------------------------------
Static Function ConMues(cTitulo, cTexto)
	Local oDlg  := NIL
	Local oMem  := NIL
	Local cMemo := cTexto

	DEFINE MSDIALOG oDlg TITLE cTitulo FROM 0, 0 TO 500, 750 PIXEL

	@ 5, 5 GET oMem VAR cMemo MEMO SIZE 365, 225 OF oDlg PIXEL
	oMem:bWhen := {|| .F. }

	@ 235, 320 BUTTON "Ok" SIZE 40, 12 OF oDlg PIXEL ACTION oDlg:End()

	ACTIVATE MSDIALOG oDlg CENTERED

Return
