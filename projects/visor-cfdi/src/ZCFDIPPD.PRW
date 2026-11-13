#INCLUDE "PROTHEUS.CH"
#INCLUDE "TOPCONN.CH"

/*/{Protheus.doc} ZCFDIPPD
Control de facturas PPD y sus complementos de pago.

POR QUE

La empresa factura mayoritariamente a credito y una parte importante
de las facturas salen con condicion de pago PPD. Una factura PPD obliga a emitir un complemento de pago por cada
cobro que se le aplique. Ese es el proceso fiscal de mas volumen de la
empresa, y hasta hoy se vigilaba desde SQL, fuera del visor.

Esta rutina lo trae adentro: cruza las facturas PPD que el visor tiene
cargadas contra los complementos de pago del mismo acervo, y dice cuales
no tienen ninguno.

COMO CRUZA

El complemento de pago (CFDI tipo P) no apunta a la factura desde la
factura, sino al reves: cada renglon del complemento trae en
ZCP_UUIDRE el folio fiscal del documento que esta pagando.

ZCP solo tiene indice por ZCP_UUID (el folio del propio complemento),
no por ZCP_UUIDRE. Asi que se recorre ZCP una vez, se arma en memoria
un resumen por documento pagado, y luego se consulta ese resumen. Una
pasada, no una busqueda por factura.

LA ADVERTENCIA QUE TRAE, Y POR QUE

Este cruce solo ve lo que el visor tiene importado. Si los complementos
de pago no estan en el acervo, TODAS las facturas PPD van a salir "sin
complemento" -- y eso no seria un hallazgo fiscal, seria un hallazgo de
que falta importar.

Es exactamente el error que ya costo tres dias en este proyecto: se
reporto que no habia complementos de pago cuando lo que pasaba era que
se estaban buscando en SF2 en vez de SEL. Por eso la rutina cuenta
primero cuantos CFDI tipo P hay cargados y lo dice ANTES que cualquier
otra cosa. Sin complementos en el acervo, el resultado no se interpreta.

@author Claude + Miguel Yasec
@since 09/2026
/*/
User Function ZCFDIPPD()
	Local aPag := {}
	Local aPpd := {}
	Local nRep := 0
	Local cTxt := ""

	If !PpdAbre()
		Return
	EndIf

	// No se usa Processa aqui a proposito: habria que asignar variables
	// locales desde dentro de un codeblock, que en ADVPL no es confiable.
	// El recorrido es de una pasada por ZCP y una por ZCF, asi que ni con
	// miles de comprobantes se nota.
	aPag := PpdPagos()
	nRep := PpdReps()
	aPpd := PpdRevisa(aPag)

	cTxt := PpdTexto(aPpd, nRep, Len(aPag))

	PpdMues("Facturas PPD y sus complementos de pago", cTxt)

Return

// ---------------------------------------------------------------------
Static Function PpdAbre()
	Local aArq := {"ZCF", "ZCP"}
	Local nI   := 0

	For nI := 1 To Len(aArq)
		If Select(aArq[nI]) == 0
			If !ChkFile(aArq[nI])
				MsgStop("No se pudo abrir " + aArq[nI] + "." + CRLF + CRLF + ;
					"Si las tablas se acaban de crear, sal del modulo y" + CRLF + ;
					"vuelve a entrar: Protheus lee el diccionario al" + CRLF + ;
					"abrir la sesion.", "ZCFDIPPD")
				Return .F.
			EndIf
		EndIf
	Next nI

	If ZCF->(LastRec()) == 0
		MsgInfo("El visor esta vacio.", "ZCFDIPPD")
		Return .F.
	EndIf

Return .T.

// ---------------------------------------------------------------------
// Resumen de lo cobrado, por documento pagado.
//
// Devuelve un arreglo de {uuidPagado, sumaPagada, saldoInsolutoUltimo,
// numeroDePagos}. Una pasada por ZCP.
//
// El saldo insoluto que se guarda es el del pago mas reciente por fecha,
// no el menor: el SAT pide que cada complemento declare cuanto queda
// DESPUES de ese pago, asi que el ultimo es el vigente. Tomar el menor
// daria un numero mas bonito y menos cierto.
// ---------------------------------------------------------------------
Static Function PpdPagos()
	Local aRet := {}
	Local nPos := 0
	Local cUui := ""
	Local dFec := CToD("")

	ZCP->(DbGoTop())
	Do While !ZCP->(Eof())

		cUui := AllTrim(ZCP->ZCP_UUIDRE)

		If Empty(cUui)
			ZCP->(DbSkip())
			Loop
		EndIf

		dFec := PpdFec("ZCP", "ZCP_FECPAG")
		nPos := aScan(aRet, {|x| x[1] == cUui })

		If nPos == 0
			aAdd(aRet, {cUui, ZCP->ZCP_SALPAG, ZCP->ZCP_SALINS, 1, dFec})
		Else
			aRet[nPos][2] += ZCP->ZCP_SALPAG
			aRet[nPos][4]++
			If Empty(aRet[nPos][5]) .Or. dFec >= aRet[nPos][5]
				aRet[nPos][3] := ZCP->ZCP_SALINS
				aRet[nPos][5] := dFec
			EndIf
		EndIf

		ZCP->(DbSkip())
	EndDo

Return aRet

// ---------------------------------------------------------------------
// Cuantos CFDI tipo P (complementos de pago) hay en el acervo.
// Es el numero que decide si el resto del reporte se puede interpretar.
// ---------------------------------------------------------------------
Static Function PpdReps()
	Local nRet := 0

	ZCF->(DbGoTop())
	Do While !ZCF->(Eof())
		If AllTrim(ZCF->ZCF_TIPCOM) == "P"
			nRet++
		EndIf
		ZCF->(DbSkip())
	EndDo

Return nRet

// ---------------------------------------------------------------------
// Clasifica cada factura PPD emitida.
//
// Que se revisa y que NO:
//
//   - Solo EMITIDAS. Una factura PPD que nos emitieron a nosotros
//     obliga al proveedor, no a la empresa.
//   - Solo tipo I (ingreso). Un egreso o un traslado no lleva
//     complemento de pago.
//   - Las CANCELADAS se marcan aparte y no cuentan como falta: una
//     factura cancelada ya no exige complemento.
//
// Estados que devuelve en la posicion 7:
//   "N" ninguno    no hay un solo complemento que la mencione
//   "P" parcial    hay complementos y todavia queda saldo insoluto
//   "S" saldado    hay complementos y el saldo insoluto llego a cero
//   "C" cancelada  no aplica
// ---------------------------------------------------------------------
Static Function PpdRevisa(aPag)
	Local aRet := {}
	Local cUui := ""
	Local nPos := 0
	Local cEst := ""
	Local nPgd := 0
	Local nIns := 0
	Local nNum := 0

	ZCF->(DbGoTop())
	Do While !ZCF->(Eof())

		If AllTrim(ZCF->ZCF_ORIGEN) != "E" .Or. ;
		   AllTrim(ZCF->ZCF_TIPCOM) != "I" .Or. ;
		   AllTrim(ZCF->ZCF_METPAG) != "PPD"
			ZCF->(DbSkip())
			Loop
		EndIf

		cUui := AllTrim(ZCF->ZCF_UUID)
		nPos := aScan(aPag, {|x| x[1] == cUui })
		nPgd := 0
		nIns := 0
		nNum := 0

		If nPos > 0
			nPgd := aPag[nPos][2]
			nIns := aPag[nPos][3]
			nNum := aPag[nPos][4]
		EndIf

		Do Case
		Case AllTrim(ZCF->ZCF_ESTSAT) == "C" ; cEst := "C"
		Case nNum == 0                       ; cEst := "N"
		Case nIns > 0                        ; cEst := "P"
		Otherwise                            ; cEst := "S"
		EndCase

		aAdd(aRet, {AllTrim(ZCF->ZCF_SERIE), ;
		            AllTrim(ZCF->ZCF_FOLIO), ;
		            DToC(PpdFec("ZCF", "ZCF_FECHA")), ;
		            AllTrim(ZCF->ZCF_RECNOM), ;
		            ZCF->ZCF_TOTAL, ;
		            nPgd, ;
		            cEst, ;
		            nNum, ;
		            cUui})

		ZCF->(DbSkip())
	EndDo

	ZCF->(DbGoTop())

Return aRet

// ---------------------------------------------------------------------
Static Function PpdTexto(aPpd, nRep, nDocPag)
	Local cRet := ""
	Local nI   := 0
	Local nN   := 0
	Local nP   := 0
	Local nS   := 0
	Local nC   := 0
	Local nMto := 0

	For nI := 1 To Len(aPpd)
		Do Case
		Case aPpd[nI][7] == "N" ; nN++ ; nMto += aPpd[nI][5]
		Case aPpd[nI][7] == "P" ; nP++
		Case aPpd[nI][7] == "S" ; nS++
		Case aPpd[nI][7] == "C" ; nC++
		EndCase
	Next nI

	// ---------- lo primero, la cobertura del acervo ----------
	cRet += "=== QUE HAY EN EL VISOR ===" + CRLF + CRLF
	cRet += "  Facturas PPD emitidas    : " + Str(Len(aPpd), 6) + CRLF
	cRet += "  Complementos de pago     : " + Str(nRep, 6) + CRLF
	cRet += "  Documentos con algun pago: " + Str(nDocPag, 6) + CRLF + CRLF

	If nRep == 0 .And. Len(aPpd) > 0
		cRet += "  *** NO HAY UN SOLO COMPLEMENTO DE PAGO CARGADO ***" + CRLF + CRLF
		cRet += "  Con eso, todas las PPD van a salir 'sin complemento'" + CRLF
		cRet += "  y ese resultado NO significa que la empresa no los emita." + CRLF
		cRet += "  Significa que no estan importados en el visor." + CRLF + CRLF
		cRet += "  Antes de reportar nada: los complementos de pago de" + CRLF
		cRet += "  los complementos viven en SEL (recibos de cobranza) y el PAC los" + CRLF
		cRet += "  deja en la carpeta que apunta MV_CFDRECP. Hay que" + CRLF
		cRet += "  importar esa carpeta primero." + CRLF + CRLF
	EndIf

	cRet += "=== RESULTADO ===" + CRLF + CRLF
	cRet += "  Sin ningun complemento   : " + Str(nN, 6) + CRLF
	cRet += "  Cobradas en parcialidades: " + Str(nP, 6) + CRLF
	cRet += "  Saldadas                 : " + Str(nS, 6) + CRLF
	cRet += "  Canceladas (no aplica)   : " + Str(nC, 6) + CRLF + CRLF

	If nN > 0
		cRet += "  Importe facturado sin un solo complemento:" + CRLF
		cRet += "     " + AllTrim(Transform(nMto, "@E 999,999,999.99")) + CRLF + CRLF
		cRet += "  OJO: que no tenga complemento no prueba que este" + CRLF
		cRet += "  vencida. Una factura recien emitida todavia no se" + CRLF
		cRet += "  cobra. Hay que leer la columna de fecha." + CRLF + CRLF
	EndIf

	// ---------- el detalle ----------
	If nN > 0
		cRet += "=== SIN NINGUN COMPLEMENTO ===" + CRLF + CRLF
		cRet += PpdEnca()
		For nI := 1 To Len(aPpd)
			If aPpd[nI][7] == "N"
				cRet += PpdRen(aPpd[nI])
			EndIf
		Next nI
		cRet += CRLF
	EndIf

	If nP > 0
		cRet += "=== COBRADAS EN PARCIALIDADES (saldo pendiente) ===" + CRLF + CRLF
		cRet += PpdEnca()
		For nI := 1 To Len(aPpd)
			If aPpd[nI][7] == "P"
				cRet += PpdRen(aPpd[nI])
			EndIf
		Next nI
		cRet += CRLF
	EndIf

	If Len(aPpd) == 0
		cRet += "No hay facturas PPD emitidas en el visor." + CRLF + CRLF
		cRet += "Si eso te sorprende, revisa dos cosas:" + CRLF
		cRet += "  1. Que el origen este calculado (boton Ver)." + CRLF
		cRet += "  2. Que las facturas traigan PPD en metodo de pago." + CRLF
	EndIf

Return cRet

// ---------------------------------------------------------------------
Static Function PpdEnca()
	Local cRet := ""

	cRet += "  " + PadR("Serie", 8) + PadR("Folio", 20) + ;
		PadR("Fecha", 12) + PadR("Receptor", 34) + ;
		PadL("Total", 15) + PadL("Pagado", 15) + "  Pagos" + CRLF
	cRet += "  " + Replicate("-", 106) + CRLF

Return cRet

// ---------------------------------------------------------------------
Static Function PpdRen(aR)
	Local cRet := ""

	cRet += "  " + PadR(aR[1], 8) + PadR(aR[2], 20) + ;
		PadR(aR[3], 12) + PadR(aR[4], 34) + ;
		PadL(AllTrim(Transform(aR[5], "@E 999,999,999.99")), 15) + ;
		PadL(AllTrim(Transform(aR[6], "@E 999,999,999.99")), 15) + ;
		Str(aR[8], 7) + CRLF

Return cRet

// ---------------------------------------------------------------------
// Una fecha puede venir como fecha o como texto AAAAMMDD, segun si la
// sesion ya recargo el diccionario. Misma historia que en el resto del
// paquete.
// ---------------------------------------------------------------------
Static Function PpdFec(cAlias, cCampo)
	Local nPos := (cAlias)->(FieldPos(cCampo))
	Local xVal := NIL

	If nPos == 0
		Return CToD("")
	EndIf

	xVal := (cAlias)->(FieldGet(nPos))

	Do Case
	Case ValType(xVal) == "D"
		Return xVal
	Case ValType(xVal) == "C" .And. Len(AllTrim(xVal)) == 8
		Return SToD(AllTrim(xVal))
	EndCase

Return CToD("")

// ---------------------------------------------------------------------
Static Function PpdMues(cTitulo, cTexto)
	Local oDlg  := NIL
	Local oMem  := NIL
	Local cMemo := cTexto

	DEFINE MSDIALOG oDlg TITLE cTitulo FROM 0, 0 TO 560, 900 PIXEL

	@ 5, 5 GET oMem VAR cMemo MEMO SIZE 440, 255 OF oDlg PIXEL
	oMem:bWhen := {|| .F. }

	DEFINE SBUTTON FROM 262, 395 TYPE 1 ACTION oDlg:End() ENABLE OF oDlg

	ACTIVATE MSDIALOG oDlg CENTERED

Return
