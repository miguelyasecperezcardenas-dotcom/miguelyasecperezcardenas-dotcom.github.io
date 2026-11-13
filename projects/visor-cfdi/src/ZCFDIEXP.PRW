#INCLUDE "PROTHEUS.CH"
#INCLUDE "TOPCONN.CH"

/*/{Protheus.doc} ZCFDIEXP
Exporta lo que hay en el visor a un archivo que se abre en Excel.

POR QUE

Todo lo que el visor encuentra se queda en la pantalla. Y la gente que
tiene que hacer algo con eso -- contabilidad, el contador externo, quien
persigue a los clientes que no pagaron -- no entra a Protheus. Necesita
el dato en un archivo.

QUE EXPORTA

Tres opciones, porque no siempre se quiere lo mismo:

  1) COMPROBANTES  un renglon por CFDI. Lo normal.
  2) CONCEPTOS     un renglon por partida. Para analizar que se vendio.
  3) PAGOS         un renglon por documento pagado. Para cobranza.

COMO SE ENTREGA

Se arma el archivo en el servidor y se copia a donde el usuario diga en
SU maquina, con CpyS2T. No se intenta abrir Excel desde aqui: si la
maquina no lo tiene, o esta ocupado, el usuario se queda viendo un error
que no dice nada. Mejor dejarle el archivo y que lo abra el.

FORMATO

CSV separado por PUNTO Y COMA, no por coma. En Windows en espanol, Excel
espera punto y coma; con coma abre todo apilado en una sola columna y
parece que el archivo salio mal. Tambien se escapan las comillas y se
quitan los saltos de linea de las descripciones, que si no rompen el
renglon.

@author Claude + Miguel Yasec
@since 09/2026
/*/
// Se cachea si ZCFDICAT esta compilado. FindFunction en cada renglon de
// un export de miles de partidas se nota; una vez por sesion no.
Static _nHayCat := -1

User Function ZCFDIEXP()
	Local nOpc := 0

	// OJO con el ancho: Aviso() dimensiona la ventana por el texto del
	// mensaje, y si los botones no caben se los lleva a un desplegable
	// de "Otras acciones" -- donde nadie los busca. Por eso el mensaje
	// trae una linea larga a proposito.
	nOpc := Aviso("Exportar a Excel", ;
		"Que se quiere en el archivo? El archivo se guarda donde tu digas." + CRLF + CRLF + ;
		"Comprobantes: un renglon por CFDI. Lo normal." + CRLF + ;
		"Conceptos   : un renglon por partida, para ver que se vendio." + CRLF + ;
		"Mas         : pagos y comercio exterior.", ;
		{"Comprobantes", "Conceptos", "Mas..."})

	Do Case
	Case nOpc == 1 ; ExpCab()
	Case nOpc == 2 ; ExpCpt()
	Case nOpc == 3 ; ExpMas()
	EndCase

Return

// ---------------------------------------------------------------------
// Segundo nivel del menu.
//
// Existe porque Aviso() admite TRES botones y ya son cuatro reportes.
// Con cuatro truena con "array out of bounds ( 4 of 3 )" y el error
// apunta a AVISO.PRX, no aqui, asi que cuesta encontrarlo.
// ---------------------------------------------------------------------
Static Function ExpMas()
	Local nOpc := 0

	nOpc := Aviso("Exportar a Excel", ;
		"Los dos reportes de detalle. El archivo se guarda donde tu digas." + CRLF + CRLF + ;
		"Pagos          : un renglon por documento pagado, con su IVA." + CRLF + ;
		"Comercio ext.  : un renglon por mercancia exportada." + CRLF + ;
		"Carta porte    : un renglon por bien transportado, con el viaje.", ;
		{"Pagos", "Comercio ext.", "Carta porte"})

	Do Case
	Case nOpc == 1 ; ExpPag()
	Case nOpc == 2 ; ExpCCE()
	Case nOpc == 3 ; ExpCart()
	EndCase

Return

// ---------------------------------------------------------------------
// 1) Un renglon por comprobante.
// ---------------------------------------------------------------------
Static Function ExpCab()
	Local cTxt := ""
	Local nN   := 0

	If !ExpAbre({"ZCF", "ZCL"})
		Return
	EndIf

	// Clave y descripcion van en COLUMNAS SEPARADAS, no pegadas en una
	// sola. Asi se puede filtrar y hacer tabla dinamica por la clave, que
	// es lo que hace contabilidad, sin perder el texto que lo explica.
	cTxt := ExpLin({"Serie", "Folio", "Fecha", "Tipo", "Origen", ;
	                "Forma pago", "Forma pago desc", ;
	                "Metodo pago", "Metodo pago desc", ;
	                "Uso CFDI", "Uso CFDI desc", ;
	                "RFC emisor", "Emisor", ;
	                "Regimen emisor", "Regimen emisor desc", ;
	                "RFC receptor", "Receptor", ;
	                "Regimen receptor", "Regimen receptor desc", ;
	                "Reg ID trib receptor", "Residencia fiscal", ;
	                "Subtotal", "Descuento", "Total", ;
	                "Moneda", "Tipo de cambio", ;
	                "Exportacion", "Exportacion desc", ;
	                "Estatus SAT", "Folio fiscal", "Archivo", ;
	                "Monto total pagos", "Base IVA 16 pagos", "IVA 16 pagos", ;
	                "Tipo relacion", "Tipo relacion desc", ;
	                "CFDI relacionados"})

	ZCF->(DbGoTop())
	Do While !ZCF->(Eof())
		nN++

		cTxt += ExpLin({AllTrim(ZCF->ZCF_SERIE), ;
		                AllTrim(ZCF->ZCF_FOLIO), ;
		                ExpFec("ZCF", "ZCF_FECHA"), ;
		                ExpTipo(ZCF->ZCF_TIPCOM), ;
		                ExpOrig(ZCF->ZCF_ORIGEN), ;
		                AllTrim(ZCF->ZCF_FORPAG), ;
		                ExpDes("c_FormaPago", ZCF->ZCF_FORPAG), ;
		                AllTrim(ZCF->ZCF_METPAG), ;
		                ExpDes("c_MetodoPago", ZCF->ZCF_METPAG), ;
		                AllTrim(ZCF->ZCF_USOCFD), ;
		                ExpDes("c_UsoCFDI", ZCF->ZCF_USOCFD), ;
		                AllTrim(ZCF->ZCF_EMIRFC), ;
		                AllTrim(ZCF->ZCF_EMINOM), ;
		                AllTrim(ZCF->ZCF_EMIREG), ;
		                ExpDes("c_RegimenFiscal", ZCF->ZCF_EMIREG), ;
		                AllTrim(ZCF->ZCF_RECRFC), ;
		                AllTrim(ZCF->ZCF_RECNOM), ;
		                AllTrim(ZCF->ZCF_RECREG), ;
		                ExpDes("c_RegimenFiscal", ZCF->ZCF_RECREG), ;
		                ExpCpo("ZCF", "ZCF_RECNRT"), ;
		                ExpCpo("ZCF", "ZCF_RECRES"), ;
		                ExpNum(ZCF->ZCF_SUBTOT), ;
		                ExpNum(ZCF->ZCF_DESCTO), ;
		                ExpNum(ZCF->ZCF_TOTAL), ;
		                AllTrim(ZCF->ZCF_MONEDA), ;
		                AllTrim(Str(ZCF->ZCF_TIPCAM, 20, 4)), ;
		                AllTrim(ZCF->ZCF_EXPORT), ;
		                ExpDes("c_Exportacion", ZCF->ZCF_EXPORT), ;
		                ExpEst(ZCF->ZCF_ESTSAT), ;
		                AllTrim(ZCF->ZCF_UUID), ;
		                AllTrim(ZCF->ZCF_ARCHIV), ;
		                ExpCpoN("ZCF", "ZCF_TOTPAG"), ;
		                ExpCpoN("ZCF", "ZCF_BASIVA"), ;
		                ExpCpoN("ZCF", "ZCF_IVA16"), ;
		                ExpRel(ZCF->ZCF_UUID, 1), ;
		                ExpRel(ZCF->ZCF_UUID, 2), ;
		                ExpRel(ZCF->ZCF_UUID, 3)})

		ZCF->(DbSkip())
	EndDo

Return ExpGrab(cTxt, "visor_comprobantes", nN, "COMPROBANTES")

// ---------------------------------------------------------------------
// 2) Un renglon por partida. Se repite el encabezado en cada renglon,
//    a proposito: asi se puede filtrar y sumar en Excel sin tener que
//    andar cruzando hojas.
// ---------------------------------------------------------------------
Static Function ExpCpt()
	Local cTxt := ""
	Local nN   := 0
	Local cUui := ""

	If !ExpAbre({"ZCF", "ZCC", "ZCA"})
		Return
	EndIf

	// El pedimento va AQUI y no solo en el reporte de comercio
	// exterior. InformacionAduanera cuelga del CONCEPTO, no del
	// complemento cce20, asi que un comprobante puede traer pedimento
	// sin ser de exportacion -- es lo normal en una importacion. En
	// homologacion pasa exactamente eso: el unico comprobante timbrado
	// con NumeroPedimento (folio 067) no tiene comercio exterior, de
	// modo que en aquel reporte el dato no aparecia por ningun lado.
	cTxt := ExpLin({"Serie", "Folio", "Fecha", "Receptor", "Folio fiscal", ;
	                "Item", ;
	                "Clave prod-serv", "Clave prod-serv desc", ;
	                "No identificacion", "Descripcion", "Cantidad", ;
	                "Unidad", "Clave unidad", "Clave unidad desc", ;
	                "Objeto impuesto", "Objeto impuesto desc", ;
	                "Valor unitario", "Importe", "Descuento", ;
	                "Pedimentos"})

	ZCC->(DbGoTop())
	Do While !ZCC->(Eof())
		nN++
		cUui := AllTrim(ZCC->ZCC_UUID)

		ExpBusca(cUui)

		cTxt += ExpLin({AllTrim(ZCF->ZCF_SERIE), ;
		                AllTrim(ZCF->ZCF_FOLIO), ;
		                ExpFec("ZCF", "ZCF_FECHA"), ;
		                AllTrim(ZCF->ZCF_RECNOM), ;
		                cUui, ;
		                AllTrim(ZCC->ZCC_ITEM), ;
		                AllTrim(ZCC->ZCC_CLAVE), ;
		                ExpDes("c_ClaveProdServ", ZCC->ZCC_CLAVE), ;
		                AllTrim(ZCC->ZCC_NOIDEN), ;
		                AllTrim(ZCC->ZCC_DESCRI), ;
		                ExpNum(ZCC->ZCC_CANT), ;
		                AllTrim(ZCC->ZCC_UNIDAD), ;
		                AllTrim(ZCC->ZCC_CLAUNI), ;
		                ExpDes("c_ClaveUnidad", ZCC->ZCC_CLAUNI), ;
		                AllTrim(ZCC->ZCC_OBJIMP), ;
		                ExpDes("c_ObjetoImp", ZCC->ZCC_OBJIMP), ;
		                ExpNum(ZCC->ZCC_VALUNI), ;
		                ExpNum(ZCC->ZCC_IMPORT), ;
		                ExpNum(ZCC->ZCC_DESCTO), ;
		                ExpPedi(cUui, ZCC->ZCC_ITEM)})

		ZCC->(DbSkip())
	EndDo

Return ExpGrab(cTxt, "visor_conceptos", nN, "CONCEPTOS")

// ---------------------------------------------------------------------
// 3) Un renglon por documento pagado.
// ---------------------------------------------------------------------
Static Function ExpPag()
	Local cTxt := ""
	Local nN   := 0
	Local cUui := ""

	If !ExpAbre({"ZCF", "ZCP", "ZCI"})
		Return
	EndIf

	cTxt := ExpLin({"Serie REP", "Folio REP", "Fecha REP", "Receptor", ;
	                "UUID del REP", "Fecha de pago", ;
	                "Forma de pago", "Forma de pago desc", ;
	                "Monto del pago", "Serie pagada", "Folio pagado", ;
	                "UUID pagado", "Parcialidad", "Saldo anterior", ;
	                "Importe pagado", "Saldo insoluto", ;
	                "No operacion", "Moneda docto", "Equivalencia DR", ;
	                "Base IVA docto", "IVA docto"})

	ZCP->(DbGoTop())
	Do While !ZCP->(Eof())
		nN++
		cUui := AllTrim(ZCP->ZCP_UUID)

		ExpBusca(cUui)

		cTxt += ExpLin({AllTrim(ZCF->ZCF_SERIE), ;
		                AllTrim(ZCF->ZCF_FOLIO), ;
		                ExpFec("ZCF", "ZCF_FECHA"), ;
		                AllTrim(ZCF->ZCF_RECNOM), ;
		                cUui, ;
		                ExpFec("ZCP", "ZCP_FECPAG"), ;
		                AllTrim(ZCP->ZCP_FORPAG), ;
		                ExpDes("c_FormaPago", ZCP->ZCP_FORPAG), ;
		                ExpNum(ZCP->ZCP_MONTO), ;
		                AllTrim(ZCP->ZCP_SERIE), ;
		                AllTrim(ZCP->ZCP_FOLIO), ;
		                AllTrim(ZCP->ZCP_UUIDRE), ;
		                AllTrim(ZCP->ZCP_PARCIA), ;
		                ExpNum(ZCP->ZCP_SALANT), ;
		                ExpNum(ZCP->ZCP_SALPAG), ;
		                ExpNum(ZCP->ZCP_SALINS), ;
		                ExpCpo("ZCP", "ZCP_NUMOPE"), ;
		                ExpCpo("ZCP", "ZCP_MONEDR"), ;
		                ExpCpo("ZCP", "ZCP_EQUIVA"), ;
		                ExpNum(ExpIvaDR(cUui, ZCP->ZCP_ITEM, 1)), ;
		                ExpNum(ExpIvaDR(cUui, ZCP->ZCP_ITEM, 2))})

		ZCP->(DbSkip())
	EndDo

Return ExpGrab(cTxt, "visor_pagos", nN, "PAGOS")

// ---------------------------------------------------------------------
// Deja ZCF parado en ese folio fiscal. Si no lo encuentra, deja el
// alias donde este: los campos saldran vacios, que es mejor que no
// exportar el renglon y que el total no cuadre.
// ---------------------------------------------------------------------
// =====================================================================
// CARTA PORTE: UN RENGLON POR BIEN TRANSPORTADO
//
// El grano es la mercancia, pero el renglon trae el viaje entero:
// origen, destino, vehiculo, permiso, poliza y operador. Una revision
// de transporte pregunta todo eso junto -- "que llevaba este camion,
// de donde a donde y quien lo manejaba" --, y partirlo en cuatro
// reportes obligaria a pegarlos a mano cada vez.
//
// Se recorre ZCT y no ZCB, por lo mismo que en comercio exterior: una
// carta porte sin mercancias tiene que verse, no desaparecer.
// =====================================================================
Static Function ExpCart()
	Local cTxt := ""
	Local nN   := 0
	Local cUui := ""
	Local nHay := 0

	If !ExpAbre({"ZCF", "ZCT", "ZCU", "ZCB", "ZCG"})
		Return
	EndIf

	// Si ZCT esta vacia no es una falla del reporte: en el acervo de
	// hoy el unico XML con cartaporte31:CartaPorte es NF_A_...038, y
	// viene SIN TIMBRE. Los sin timbre se van a ZCR y nunca llegan al
	// visor, asi que no hay carta porte que exportar. Se dice con todas
	// sus letras para que dentro de un mes no parezca un bug.
	If ZCT->(LastRec()) == 0
		MsgInfo("No hay carta porte cargada." + CRLF + CRLF + ;
			"El acervo actual trae un solo comprobante con complemento" + CRLF + ;
			"de carta porte y esta SIN TIMBRE, por lo que no entra al" + CRLF + ;
			"visor. El reporte esta listo: en cuanto llegue una carta" + CRLF + ;
			"porte timbrada aparecera aqui.", "ZCFDIEXP")
		Return
	EndIf

	cTxt := ExpLin({"Serie", "Folio", "Fecha", "Folio fiscal", ;
	                "IdCCP", "Version CP", "Transp internac", ;
	                "Distancia total", ;
	                "Origen RFC", "Origen nombre", "Origen fecha", ;
	                "Origen CP", "Origen estado", ;
	                "Destino RFC", "Destino nombre", "Destino fecha", ;
	                "Destino CP", "Destino estado", ;
	                "Placa", "Anio modelo", "Config vehicular", ;
	                "Permiso SCT", "Num permiso SCT", ;
	                "Aseguradora", "Poliza", "Figuras de transporte", ;
	                "Peso bruto total", "Unidad peso", "Total mercancias", ;
	                "Bienes transp", "Descripcion", "Cantidad", ;
	                "Clave unidad", "Peso en Kg", "Valor", "Moneda"})

	ZCT->(DbGoTop())
	Do While !ZCT->(Eof())
		cUui := AllTrim(ZCT->ZCT_UUID)

		ExpBusca(cUui)

		nHay := 0
		ZCB->(DbGoTop())
		Do While !ZCB->(Eof())
			If AllTrim(ZCB->ZCB_UUID) == cUui
				nHay++
				nN++
				cTxt += ExpCartLin(cUui, .T.)
			EndIf
			ZCB->(DbSkip())
		EndDo

		If nHay == 0
			nN++
			cTxt += ExpCartLin(cUui, .F.)
		EndIf

		ZCT->(DbSkip())
	EndDo

Return ExpGrab(cTxt, "visor_carta_porte", nN, "CARTA PORTE")

// ---------------------------------------------------------------------
Static Function ExpCartLin(cUuid, lMer)
	Local aFin := {}

	aFin := {AllTrim(ZCF->ZCF_SERIE), ;
	         AllTrim(ZCF->ZCF_FOLIO), ;
	         ExpFec("ZCF", "ZCF_FECHA"), ;
	         cUuid, ;
	         ExpCpo("ZCT", "ZCT_IDCCP"), ;
	         ExpCpo("ZCT", "ZCT_VERSIO"), ;
	         ExpCpo("ZCT", "ZCT_TRAINT"), ;
	         ExpCpoN("ZCT", "ZCT_TOTDIS"), ;
	         ExpUbi(cUuid, "ORIGEN",  1), ;
	         ExpUbi(cUuid, "ORIGEN",  2), ;
	         ExpUbi(cUuid, "ORIGEN",  3), ;
	         ExpUbi(cUuid, "ORIGEN",  4), ;
	         ExpUbi(cUuid, "ORIGEN",  5), ;
	         ExpUbi(cUuid, "DESTINO", 1), ;
	         ExpUbi(cUuid, "DESTINO", 2), ;
	         ExpUbi(cUuid, "DESTINO", 3), ;
	         ExpUbi(cUuid, "DESTINO", 4), ;
	         ExpUbi(cUuid, "DESTINO", 5), ;
	         ExpCpo("ZCT", "ZCT_PLACA"), ;
	         ExpCpo("ZCT", "ZCT_ANIOVM"), ;
	         ExpCpo("ZCT", "ZCT_CONFVE"), ;
	         ExpCpo("ZCT", "ZCT_PERSCT"), ;
	         ExpCpo("ZCT", "ZCT_NUMPER"), ;
	         ExpCpo("ZCT", "ZCT_ASEGUR"), ;
	         ExpCpo("ZCT", "ZCT_POLIZA"), ;
	         ExpFig(cUuid), ;
	         ExpCpoN("ZCT", "ZCT_PESBRU"), ;
	         ExpCpo("ZCT", "ZCT_UNIPES"), ;
	         ExpCpo("ZCT", "ZCT_NUMMER")}

	If lMer
		aAdd(aFin, ExpCpo("ZCB", "ZCB_BIENES"))
		aAdd(aFin, ExpCpo("ZCB", "ZCB_DESCRI"))
		aAdd(aFin, ExpCpoN("ZCB", "ZCB_CANT"))
		aAdd(aFin, ExpCpo("ZCB", "ZCB_CLAUNI"))
		aAdd(aFin, ExpCpoN("ZCB", "ZCB_PESKG"))
		aAdd(aFin, ExpCpoN("ZCB", "ZCB_VALOR"))
		aAdd(aFin, ExpCpo("ZCB", "ZCB_MONEDA"))
	Else
		aAdd(aFin, "")
		aAdd(aFin, "")
		aAdd(aFin, "")
		aAdd(aFin, "")
		aAdd(aFin, "")
		aAdd(aFin, "")
		aAdd(aFin, "")
	EndIf

Return ExpLin(aFin)

// ---------------------------------------------------------------------
// UN DATO DE LAS UBICACIONES, POR TIPO
//
// Origen y destino van en columnas propias en vez de una lista pegada,
// porque lo que se pregunta de una carta porte es "de donde a donde", y
// eso en Excel se filtra y se ordena. Si hubiera mas de una parada del
// mismo tipo se listan todas separadas por barra -- se ve raro, y se
// ve, que es justo lo que se quiere.
//
// nQue: 1 RFC, 2 nombre, 3 fecha y hora, 4 codigo postal, 5 estado.
// ---------------------------------------------------------------------
Static Function ExpUbi(cUuid, cTipo, nQue)
	Local cRet := ""
	Local nRec := 0
	Local cDat := ""

	If Select("ZCU") == 0
		Return ""
	EndIf

	nRec := ZCU->(Recno())

	ZCU->(DbGoTop())
	Do While !ZCU->(Eof())
		If AllTrim(ZCU->ZCU_UUID) == AllTrim(cUuid) .And. ;
			Upper(AllTrim(ZCU->ZCU_TIPO)) == cTipo

			Do Case
			Case nQue == 1 ; cDat := AllTrim(ZCU->ZCU_RFC)
			Case nQue == 2 ; cDat := AllTrim(ZCU->ZCU_NOMBRE)
			Case nQue == 3 ; cDat := ExpFec("ZCU", "ZCU_FECHA") + ;
			                         " " + AllTrim(ZCU->ZCU_HORA)
			Case nQue == 4 ; cDat := AllTrim(ZCU->ZCU_CP)
			Case nQue == 5 ; cDat := AllTrim(ZCU->ZCU_ESTADO)
			Otherwise      ; cDat := ""
			EndCase

			If !Empty(cDat)
				If !Empty(cRet)
					cRet += " | "
				EndIf
				cRet += cDat
			EndIf
		EndIf
		ZCU->(DbSkip())
	EndDo

	ZCU->(DbGoTo(nRec))

Return cRet

// ---------------------------------------------------------------------
// LAS FIGURAS DE TRANSPORTE, EN UNA COLUMNA
//
// Casi siempre es una sola -- el operador --, pero pueden venir el
// propietario y el arrendatario. Se listan todas con su licencia: es
// el dato que pide una revision en carretera y el que no se puede
// perder por quedarse con el primero.
// ---------------------------------------------------------------------
Static Function ExpFig(cUuid)
	Local cRet := ""
	Local nRec := 0
	Local cUno := ""

	If Select("ZCG") == 0
		Return ""
	EndIf

	nRec := ZCG->(Recno())

	ZCG->(DbGoTop())
	Do While !ZCG->(Eof())
		If AllTrim(ZCG->ZCG_UUID) == AllTrim(cUuid)
			cUno := AllTrim(ZCG->ZCG_TIPFIG) + " " + ;
				AllTrim(ZCG->ZCG_NOMBRE) + ;
				" (" + AllTrim(ZCG->ZCG_RFC)
			If !Empty(AllTrim(ZCG->ZCG_LICENC))
				cUno += ", lic " + AllTrim(ZCG->ZCG_LICENC)
			EndIf
			cUno += ")"

			If !Empty(cRet)
				cRet += " | "
			EndIf
			cRet += cUno
		EndIf
		ZCG->(DbSkip())
	EndDo

	ZCG->(DbGoTo(nRec))

Return cRet

// =====================================================================
// COMERCIO EXTERIOR: UN RENGLON POR MERCANCIA
//
// Se recorre ZCE (la cabecera) y no ZCM, aunque el renglon sea de
// mercancia. La razon no es de estilo: si se recorriera ZCM, un
// comprobante de exportacion que por lo que sea no trajera mercancias
// desapareceria del reporte sin dejar rastro, y un comprobante que
// falta en silencio es peor que una celda vacia. Recorriendo la
// cabecera, ese caso sale igual, con las columnas de mercancia en
// blanco, y se nota.
// =====================================================================
Static Function ExpCCE()
	Local cTxt := ""
	Local nN   := 0
	Local cUui := ""
	Local nHay := 0

	If !ExpAbre({"ZCF", "ZCE", "ZCM", "ZCA"})
		Return
	EndIf

	cTxt := ExpLin({"Serie", "Folio", "Fecha", "Receptor", "Folio fiscal", ;
	                "Clave pedimento", "Incoterm", "Certificado origen", ;
	                "Motivo traslado", "Tipo cambio USD", "Total USD", ;
	                "Reg ID trib receptor", "Pais receptor", ;
	                "Pais emisor", ;
	                "No identificacion", "Fraccion arancelaria", ;
	                "Cantidad aduana", "Unidad aduana", ;
	                "Valor unitario aduana", "Valor dolares", ;
	                "Pedimentos del CFDI"})

	ZCE->(DbGoTop())
	Do While !ZCE->(Eof())
		cUui := AllTrim(ZCE->ZCE_UUID)

		ExpBusca(cUui)

		nHay := 0
		ZCM->(DbGoTop())
		Do While !ZCM->(Eof())
			If AllTrim(ZCM->ZCM_UUID) == cUui
				nHay++
				nN++
				cTxt += ExpCCELin(cUui, .T.)
			EndIf
			ZCM->(DbSkip())
		EndDo

		// Sin mercancias: el comprobante sale igual, en blanco.
		If nHay == 0
			nN++
			cTxt += ExpCCELin(cUui, .F.)
		EndIf

		ZCE->(DbSkip())
	EndDo

Return ExpGrab(cTxt, "visor_comercio_ext", nN, "COMERCIO EXTERIOR")

// ---------------------------------------------------------------------
// Un renglon del reporte. lMer dice si hay que leer la mercancia en la
// que ZCM esta parado o dejar esas columnas vacias.
// ---------------------------------------------------------------------
Static Function ExpCCELin(cUuid, lMer)
	Local aFin := {}

	aFin := {AllTrim(ZCF->ZCF_SERIE), ;
	         AllTrim(ZCF->ZCF_FOLIO), ;
	         ExpFec("ZCF", "ZCF_FECHA"), ;
	         AllTrim(ZCF->ZCF_RECNOM), ;
	         cUuid, ;
	         ExpCpo("ZCE", "ZCE_CVEPED"), ;
	         ExpCpo("ZCE", "ZCE_INCOTE"), ;
	         ExpCpo("ZCE", "ZCE_CERORI"), ;
	         ExpCpo("ZCE", "ZCE_MOTTRA"), ;
	         ExpCpoN("ZCE", "ZCE_TIPCAM"), ;
	         ExpCpoN("ZCE", "ZCE_TOTUSD"), ;
	         ExpCpo("ZCE", "ZCE_RECNRT"), ;
	         ExpCpo("ZCE", "ZCE_RECPAI"), ;
	         ExpCpo("ZCE", "ZCE_EMIPAI")}

	If lMer
		aAdd(aFin, ExpCpo("ZCM", "ZCM_NOIDEN"))
		aAdd(aFin, ExpCpo("ZCM", "ZCM_FRACC"))
		aAdd(aFin, ExpCpoN("ZCM", "ZCM_CANADU"))
		aAdd(aFin, ExpCpo("ZCM", "ZCM_UNIADU"))
		aAdd(aFin, ExpCpoN("ZCM", "ZCM_VALUNI"))
		aAdd(aFin, ExpCpoN("ZCM", "ZCM_VALDOL"))
	Else
		aAdd(aFin, "")
		aAdd(aFin, "")
		aAdd(aFin, "")
		aAdd(aFin, "")
		aAdd(aFin, "")
		aAdd(aFin, "")
	EndIf

	aAdd(aFin, ExpPedi(cUuid))

Return ExpLin(aFin)

// ---------------------------------------------------------------------
// LOS CFDI RELACIONADOS DE UN COMPROBANTE
//
// Tres columnas en vez de una sola con todo pegado, porque en Excel se
// filtra por tipo de relacion ("ensename las notas de credito") mucho
// mas seguido de lo que se lee un UUID. Si un comprobante tuviera dos
// tipos distintos, la columna de tipo los lista los dos y no se pierde
// nada.
//
// nQue: 1 = tipos, 2 = descripcion de los tipos, 3 = los UUID.
// ---------------------------------------------------------------------
Static Function ExpRel(cUuid, nQue)
	Local cRet := ""
	Local cDes := ""
	Local nRec := 0
	Local aTip := {}
	Local nI   := 0

	If Select("ZCL") == 0
		Return ""
	EndIf

	nRec := ZCL->(Recno())

	ZCL->(DbGoTop())
	Do While !ZCL->(Eof())
		If AllTrim(ZCL->ZCL_UUID) == AllTrim(cUuid)
			If nQue == 3
				If !Empty(cRet)
					cRet += " | "
				EndIf
				cRet += AllTrim(ZCL->ZCL_UUIDRE)
			Else
				// los tipos no se repiten: un comprobante con tres
				// relacionados del mismo tipo tiene UN tipo, no tres.
				If aScan(aTip, {|x| x == AllTrim(ZCL->ZCL_TIPREL) }) == 0
					aAdd(aTip, AllTrim(ZCL->ZCL_TIPREL))
				EndIf
			EndIf
		EndIf
		ZCL->(DbSkip())
	EndDo

	ZCL->(DbGoTo(nRec))

	If nQue == 3
		Return cRet
	EndIf

	For nI := 1 To Len(aTip)
		If !Empty(cRet)
			cRet += " | "
		EndIf
		If nQue == 1
			cRet += aTip[nI]
		Else
			cDes := ExpDes("c_TipoRelacion", aTip[nI])
			cRet += IIf(Empty(cDes), aTip[nI], cDes)
		EndIf
	Next nI

Return cRet

// ---------------------------------------------------------------------
// Los pedimentos del comprobante, separados por barra.
//
// El pedimento cuelga del CONCEPTO y este reporte va por mercancia, que
// es otro grano, asi que no hay forma honesta de ponerlo en su propia
// columna renglon por renglon. Se listan TODOS los del comprobante en
// vez de quedarse con el primero: una celda con dos pedimentos se ve y
// se pregunta; una que se comio el segundo, no.
// ---------------------------------------------------------------------
Static Function ExpPedi(cUuid, cItem)
	Local cRet := ""
	Local nRec := 0
	Local lOk  := .F.

	// Sin item: todos los del comprobante (reporte de comercio
	// exterior, que va por mercancia). Con item: solo los de ese
	// concepto (reporte de conceptos, que va por partida).
	Default cItem := ""

	If Select("ZCA") == 0
		Return ""
	EndIf

	nRec := ZCA->(Recno())

	ZCA->(DbGoTop())
	Do While !ZCA->(Eof())
		lOk := AllTrim(ZCA->ZCA_UUID) == AllTrim(cUuid)
		If lOk .And. !Empty(cItem)
			lOk := AllTrim(ZCA->ZCA_ITEM) == AllTrim(cItem)
		EndIf
		If lOk
			If !Empty(cRet)
				cRet += " | "
			EndIf
			cRet += AllTrim(ZCA->ZCA_PEDIME)
		EndIf
		ZCA->(DbSkip())
	EndDo

	ZCA->(DbGoTo(nRec))

Return cRet

// ---------------------------------------------------------------------
Static Function ExpBusca(cUuid)
	Local lOk := .F.

	ZCF->(DbGoTop())
	Do While !ZCF->(Eof())
		If AllTrim(ZCF->ZCF_UUID) == cUuid
			lOk := .T.
			Exit
		EndIf
		ZCF->(DbSkip())
	EndDo

Return lOk

// ---------------------------------------------------------------------
// Arma un renglon de CSV. Punto y coma, comillas escapadas, y sin
// saltos de linea adentro de un campo.
// ---------------------------------------------------------------------
Static Function ExpLin(aCpo)
	Local cRet := ""
	Local cVal := ""
	Local nI   := 0

	For nI := 1 To Len(aCpo)

		cVal := aCpo[nI]

		cVal := StrTran(cVal, CRLF, " ")
		cVal := StrTran(cVal, Chr(13), " ")
		cVal := StrTran(cVal, Chr(10), " ")
		cVal := StrTran(cVal, '"', "'")

		cRet += IIf(nI > 1, ";", "")
		cRet += '"' + AllTrim(cVal) + '"'
	Next nI

Return cRet + CRLF

// ---------------------------------------------------------------------
// Graba en el servidor y lo copia a la maquina del usuario.
// ---------------------------------------------------------------------
// cQue es el nombre de lo que se exporto, y va en el mensaje final a
// proposito: Aviso() acomoda los botones en un orden distinto al del
// arreglo, asi que conviene que el usuario pueda comprobar que le toco
// lo que pidio en vez de confiar en la posicion del boton.
Static Function ExpGrab(cTxt, cNom, nN, cQue)
	Local cSrv := ""
	Local cCli := ""
	Local aCar := {}
	Local cArc := ""
	Local nI   := 0

	If nN == 0
		MsgInfo("No hay nada que exportar.", "ZCFDIEXP")
		Return
	EndIf

	// NO SE PREGUNTA DONDE GUARDAR, A PROPOSITO.
	//
	// Aqui hubo primero un cGetFile y luego un ParamBox, y los dos
	// quedaron feos: ventanas enormes, etiquetas cortadas, barras de
	// desplazamiento. No vale la pena pelearse con el control para una
	// pregunta que casi siempre tiene la misma respuesta. Se guarda en
	// una carpeta conocida, se dice cual, y el que quiera otra lo mueve.
	//
	// OJO CON CpyS2T: el destino es una CARPETA, no la ruta completa del
	// archivo. Si se le manda "C:\algo.csv" le pega una diagonal al final
	// y contesta "Directory c:\algo.csv\ does not exist" -- que suena a
	// que la carpeta no existe, cuando el problema es que le estabamos
	// dando un archivo donde esperaba una carpeta.
	aCar := {"C:\TOTVS\", "C:\Temp\", "C:\"}

	// La HORA va en el nombre a proposito. Con solo la fecha, exportar
	// dos veces el mismo dia reusa el nombre -- y si el archivo anterior
	// esta abierto en Excel, Windows no deja sobrescribirlo y CpyS2T
	// falla con "Directory ... does not exist", que no tiene nada que
	// ver con lo que realmente pasa.
	cArc := cNom + "_" + DToS(Date()) + "_" + ;
	        StrTran(Left(Time(), 5), ":", "") + ".csv"
	cSrv := "\system\" + cArc

	// "sep=;" en la PRIMERA linea le dice a Excel cual es el separador,
	// y le gana a la configuracion regional de Windows. Sin esto, en una
	// maquina configurada con coma el archivo se abre todo apilado en la
	// columna A y parece que salio mal.
	//
	// Excel se come esa linea, no la muestra. Otros programas (Notepad,
	// LibreOffice) la ven como un renglon mas, que es un precio barato.
	MemoWrite(cSrv, "sep=;" + CRLF + cTxt)

	If !File(cSrv)
		MsgStop("No se pudo escribir el archivo en el servidor:" + CRLF + ;
			cSrv, "ZCFDIEXP")
		Return
	EndIf

	// Se intenta en varias carpetas: la primera que acepte, gana.
	For nI := 1 To Len(aCar)
		If CpyS2T(cSrv, aCar[nI], .T.)
			cCli := aCar[nI] + cArc
			Exit
		EndIf
	Next nI

	If Empty(cCli)
		MsgStop("El archivo se creo en el servidor pero no se pudo" + CRLF + ;
			"copiar a tu maquina. Se intento en:" + CRLF + CRLF + ;
			"  C:\TOTVS\ , C:\Temp\ , C:\" + CRLF + CRLF + ;
			"Causas mas comunes, en orden:" + CRLF + ;
			"  1. La carpeta no existe en tu maquina." + CRLF + ;
			"  2. No tienes permiso de escribir ahi (C:\ casi nunca)." + CRLF + ;
			"  3. Hay un archivo con ese nombre ABIERTO en Excel." + CRLF + CRLF + ;
			"Esta en el servidor, en:" + CRLF + cSrv, "ZCFDIEXP")
		Return
	EndIf

	MsgInfo("Listo. Se exporto: " + cQue + CRLF + CRLF + ;
		cValToChar(nN) + " renglon(es) exportado(s) a:" + CRLF + ;
		cCli, "ZCFDIEXP")

Return

// ---------------------------------------------------------------------
Static Function ExpAbre(aArq)
	Local nI := 0

	For nI := 1 To Len(aArq)
		If Select(aArq[nI]) == 0
			ChkFile(aArq[nI])
		EndIf
		If Select(aArq[nI]) == 0
			MsgStop("No se pudo abrir " + aArq[nI] + ".", "ZCFDIEXP")
			Return .F.
		EndIf
	Next nI

	If ZCF->(LastRec()) == 0
		MsgInfo("No hay comprobantes cargados.", "ZCFDIEXP")
		Return .F.
	EndIf

Return .T.

// ---------------------------------------------------------------------
// Una fecha puede venir como fecha o como texto AAAAMMDD.
// ---------------------------------------------------------------------
Static Function ExpFec(cAlias, cCampo)
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
// Un numero para Excel: punto decimal, sin separador de miles. Si se le
// mete la coma de los miles, Excel en espanol lo lee como texto.
// ---------------------------------------------------------------------
Static Function ExpNum(nVal)
Return AllTrim(Str(nVal, 20, 2))

// ---------------------------------------------------------------------
// Un campo numerico que puede no existir todavia en la tabla abierta.
// ExpCpo sirve para texto; este formatea a dos decimales para que el
// Excel no reciba "1234.5" en una columna de dinero.
// ---------------------------------------------------------------------
Static Function ExpCpoN(cAlias, cCampo)
	Local nPos := (cAlias)->(FieldPos(cCampo))

	If nPos == 0
		Return ""
	EndIf

Return AllTrim(Str((cAlias)->(FieldGet(nPos)), 20, 2))

// ---------------------------------------------------------------------
// EL IVA DE UN DOCUMENTO RELACIONADO
//
// Esta es la columna que contesta la pregunta del IVA de los PPD: hasta
// ahora el renglon decia cuanto se pago, pero no cuanto de eso era IVA,
// y sin ese dato no se puede cuadrar un complemento contra nada.
//
// Vive en ZCI con nivel 'D' y el mismo item del ZCP. Se SUMA en vez de
// tomar el primero porque un documento puede traer mas de un traslado,
// y quedarse con uno solo es la clase de error que nadie nota hasta que
// las sumas no cuadran por centavos.
//
// nQue: 1 = base, 2 = importe.
// ---------------------------------------------------------------------
Static Function ExpIvaDR(cUuid, cItem, nQue)
	Local nRet := 0
	Local nRec := 0
	Local cBus := ""

	If Select("ZCI") == 0
		Return 0
	EndIf

	nRec := ZCI->(Recno())

	// El item del nivel 'D' lleva la letra adelante ("D001"), para que
	// no choque con el del nivel 'P' en el indice unico de ZCI, que no
	// incluye ZCI_NIVEL. ZCP_ITEM viene como "0001", asi que hay que
	// armarlo igual para encontrarlo.
	cBus := "D" + Right(AllTrim(cItem), 3)

	ZCI->(DbGoTop())
	Do While !ZCI->(Eof())
		If AllTrim(ZCI->ZCI_UUID) == AllTrim(cUuid) .And. ;
			AllTrim(ZCI->ZCI_ITEM) == cBus .And. ;
			ZCI->ZCI_NIVEL == "D" .And. ZCI->ZCI_TIPO == "T"
			nRet += IIf(nQue == 1, ZCI->ZCI_BASE, ZCI->ZCI_IMPORT)
		EndIf
		ZCI->(DbSkip())
	EndDo

	ZCI->(DbGoTo(nRec))

Return nRet

// ---------------------------------------------------------------------
// Descripcion de una clave del SAT, para la columna de al lado.
//
// Devuelve SOLO el texto, no "clave - texto": la clave ya va en su propia
// columna. Si ZCFDICAT no esta compilado, o la clave no esta en el
// catalogo, devuelve vacio -- el export no se cae por eso.
// ---------------------------------------------------------------------
Static Function ExpDes(cCat, cClave)
	Local cCla := AllTrim(cValToChar(cClave))
	Local cDes := ""

	If Empty(cCla)
		Return ""
	EndIf

	If _nHayCat == -1
		_nHayCat := IIf(FindFunction("U_ZCATDES"), 1, 0)
	EndIf

	If _nHayCat == 0
		Return ""
	EndIf

	cDes := AllTrim(U_ZCATDES(cCat, cCla))

	// U_ZCATDES devuelve la clave misma cuando no la encuentra.
	If cDes == cCla
		Return ""
	EndIf

Return cDes

// ---------------------------------------------------------------------
Static Function ExpTipo(cTipo)
	Local cRet := ""

	Do Case
	Case AllTrim(cTipo) == "I" ; cRet := "ingreso"
	Case AllTrim(cTipo) == "E" ; cRet := "egreso"
	Case AllTrim(cTipo) == "T" ; cRet := "traslado"
	Case AllTrim(cTipo) == "N" ; cRet := "nomina"
	Case AllTrim(cTipo) == "P" ; cRet := "pago"
	Otherwise                  ; cRet := "?"
	EndCase

Return cRet

// ---------------------------------------------------------------------
// Un campo que puede no existir todavia en la tabla.
//
// Los campos nuevos entran con Construir - Crear tablas. Si alguien
// exporta antes de correr eso, es mejor una columna vacia que un error.
// ---------------------------------------------------------------------
Static Function ExpCpo(cAlias, cCampo)
	Local nPos := (cAlias)->(FieldPos(cCampo))

	If nPos == 0
		Return ""
	EndIf

Return AllTrim(cValToChar((cAlias)->(FieldGet(nPos))))

// ---------------------------------------------------------------------
Static Function ExpOrig(cOri)
	Local cRet := ""

	Do Case
	Case AllTrim(cOri) == "E" ; cRet := "emitido"
	Case AllTrim(cOri) == "R" ; cRet := "recibido"
	Case AllTrim(cOri) == "?" ; cRet := "indeterminado"
	Otherwise                 ; cRet := "sin calcular"
	EndCase

Return cRet

// ---------------------------------------------------------------------
Static Function ExpEst(cEst)
	Local cRet := ""

	Do Case
	Case AllTrim(cEst) == "C" ; cRet := "CANCELADO"
	Case AllTrim(cEst) == "V" ; cRet := "vigente segun el SAT"
	Case AllTrim(cEst) == "N" ; cRet := "EL SAT NO CONOCE ESTE FOLIO"
	Otherwise                 ; cRet := "sin consultar al SAT"
	EndCase

Return cRet
