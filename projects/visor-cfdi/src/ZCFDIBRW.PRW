#INCLUDE "PROTHEUS.CH"
#INCLUDE "TOPCONN.CH"

/*/{Protheus.doc} ZCFDIBRW
Browse de las partidas del comprobante donde esta parado el visor.

POR QUE UNA SOLA OPCION Y NO UNA POR TABLA

El visor ya tiene doce opciones en el menu. Agregar una por cada tabla
hija (conceptos, impuestos, pagos, mercancias, relacionados) lo volveria
ilegible, y son todas la misma operacion: ver los renglones que cuelgan
de ESTE folio fiscal. Asi que es una sola entrada, "Partidas", que
pregunta de que tabla.

POR QUE EL FILTRO VA SOBRE EL ALIAS

Mismo motivo que en U_ZCFDIORG: FWBrowse recorre el alias, asi que un
DbSetFilter le llega igual y no depende de la version del framework de
este ambiente. El filtro SE QUITA al cerrar -- si se queda puesto, la
siguiente rutina que abra esa tabla ve solo un comprobante y nadie
entiende por que.

POR QUE LAS COLUMNAS SE PIDEN POR NOMBRE Y NO POR POSICION

BrwDato resuelve el campo con FieldPos cada vez. Un campo que la sesion
todavia no ve (el diccionario se lee al abrir Protheus) sale en blanco
en vez de tronar el browse entero. Es el mismo trato que ya hace la
exportacion con ExpCpo, y por la misma razon: en este proyecto los
campos nuevos aparecen seguido.
/*/

// ---------------------------------------------------------------------
User Function ZCFDIPAR()
	Local nOpc := 0

	If Select("ZCF") == 0 .Or. Empty(ZCF->ZCF_UUID)
		MsgStop("No hay un comprobante seleccionado.", "ZCFDIBRW")
		Return
	EndIf

	// Aviso() admite tres botones. Con cuatro truena con "array out of
	// bounds ( 4 of 3 )" y el error apunta a AVISO.PRX, no aqui.
	nOpc := Aviso("Partidas del comprobante", ;
		"Folio fiscal: " + AllTrim(ZCF->ZCF_UUID) + CRLF + CRLF + ;
		"Conceptos : los renglones de la factura" + CRLF + ;
		"Impuestos : traslados y retenciones, de los cuatro niveles" + CRLF + ;
		"Mas...    : pagos, comercio exterior y relacionados", ;
		{"Conceptos", "Impuestos", "Mas..."}, 3)

	Do Case
	Case nOpc == 1
		BrwZCC()
	Case nOpc == 2
		BrwZCI()
	Case nOpc == 3
		BrwMas()
	EndCase

Return

// ---------------------------------------------------------------------
Static Function BrwMas()
	Local nOpc := 0

	nOpc := Aviso("Partidas del comprobante", ;
		"Pagos         : el complemento de pago (solo en tipo P)" + CRLF + ;
		"Comercio ext. : las mercancias de exportacion" + CRLF + ;
		"Relacionados  : los CFDI que este comprobante referencia", ;
		{"Pagos", "Comercio ext.", "Relacionados"}, 3)

	Do Case
	Case nOpc == 1
		BrwZCP()
	Case nOpc == 2
		BrwZCM()
	Case nOpc == 3
		BrwZCL()
	EndCase

Return

// ---------------------------------------------------------------------
// LAS TABLAS
// ---------------------------------------------------------------------
Static Function BrwZCC()
	Local aCol := {}

	aAdd(aCol, BrwCol("Item",      "ZCC", "ZCC_ITEM",   "C",  6))
	aAdd(aCol, BrwCol("Clave SAT", "ZCC", "ZCC_CLAVE",  "C", 12))
	aAdd(aCol, BrwCol("Interna",   "ZCC", "ZCC_NOIDEN", "C", 16))
	aAdd(aCol, BrwCol("Descripcion","ZCC","ZCC_DESCRI", "C", 50))
	aAdd(aCol, BrwCol("Cantidad",  "ZCC", "ZCC_CANT",   "N", 14))
	aAdd(aCol, BrwCol("Unidad",    "ZCC", "ZCC_UNIDAD", "C",  8))
	aAdd(aCol, BrwCol("Cve unidad","ZCC", "ZCC_CLAUNI", "C", 10))
	aAdd(aCol, BrwCol("Val unit",  "ZCC", "ZCC_VALUNI", "N", 14))
	aAdd(aCol, BrwCol("Descuento", "ZCC", "ZCC_DESCTO", "N", 14))
	aAdd(aCol, BrwCol("Importe",   "ZCC", "ZCC_IMPORT", "N", 14))
	aAdd(aCol, BrwCol("Obj imp",   "ZCC", "ZCC_OBJIMP", "C",  8))

	BrwAbre("ZCC", "ZCC_UUID", "Conceptos", aCol)

Return

// ---------------------------------------------------------------------
// ZCI junta los cuatro niveles en una sola tabla, asi que el nivel es
// la primera columna: sin el, un traslado del concepto y uno del
// comprobante se ven identicos y las sumas no cuadran con nada.
// ---------------------------------------------------------------------
Static Function BrwZCI()
	Local aCol := {}

	aAdd(aCol, BrwCol("Nivel",    "ZCI", "ZCI_NIVEL",  "C",  6))
	aAdd(aCol, BrwCol("Item",     "ZCI", "ZCI_ITEM",   "C",  8))
	aAdd(aCol, BrwCol("Seq",      "ZCI", "ZCI_SEQ",    "C",  6))
	aAdd(aCol, BrwCol("T/R",      "ZCI", "ZCI_TIPO",   "C",  5))
	aAdd(aCol, BrwCol("Impuesto", "ZCI", "ZCI_IMPUES", "C", 10))
	aAdd(aCol, BrwCol("Base",     "ZCI", "ZCI_BASE",   "N", 14))
	aAdd(aCol, BrwCol("Factor",   "ZCI", "ZCI_TIPFAC", "C", 10))
	aAdd(aCol, BrwCol("Tasa",     "ZCI", "ZCI_TASA",   "N", 12))
	aAdd(aCol, BrwCol("Importe",  "ZCI", "ZCI_IMPORT", "N", 14))

	BrwAbre("ZCI", "ZCI_UUID", "Impuestos (C concepto, G comprobante, " + ;
		"L local, D docto relacionado, P pago)", aCol)

Return

// ---------------------------------------------------------------------
Static Function BrwZCP()
	Local aCol := {}

	aAdd(aCol, BrwCol("Item",      "ZCP", "ZCP_ITEM",   "C",  8))
	aAdd(aCol, BrwCol("Fecha pago","ZCP", "ZCP_FECPAG", "C", 12))
	aAdd(aCol, BrwCol("Forma pago","ZCP", "ZCP_FORPAG", "C",  8))
	aAdd(aCol, BrwCol("Moneda",    "ZCP", "ZCP_MONEDA", "C",  8))
	aAdd(aCol, BrwCol("T.cambio",  "ZCP", "ZCP_TIPCAM", "N", 12))
	aAdd(aCol, BrwCol("Monto",     "ZCP", "ZCP_MONTO",  "N", 14))
	aAdd(aCol, BrwCol("Num oper",  "ZCP", "ZCP_NUMOPE", "C", 20))
	aAdd(aCol, BrwCol("UUID rel",  "ZCP", "ZCP_UUIDRE", "C", 38))
	aAdd(aCol, BrwCol("Serie",     "ZCP", "ZCP_SERIE",  "C",  8))
	aAdd(aCol, BrwCol("Folio",     "ZCP", "ZCP_FOLIO",  "C", 16))
	aAdd(aCol, BrwCol("Parcial",   "ZCP", "ZCP_PARCIA", "C",  8))
	aAdd(aCol, BrwCol("Saldo ant", "ZCP", "ZCP_SALANT", "N", 14))
	aAdd(aCol, BrwCol("Pagado",    "ZCP", "ZCP_SALPAG", "N", 14))
	aAdd(aCol, BrwCol("Saldo ins", "ZCP", "ZCP_SALINS", "N", 14))
	aAdd(aCol, BrwCol("IVA pago",  "ZCP", "ZCP_IVAPAG", "N", 14))
	aAdd(aCol, BrwCol("Mon DR",    "ZCP", "ZCP_MONEDR", "C",  8))
	aAdd(aCol, BrwCol("Equiv DR",  "ZCP", "ZCP_EQUIVA", "N", 12))

	BrwAbre("ZCP", "ZCP_UUID", "Complemento de pago", aCol)

Return

// ---------------------------------------------------------------------
Static Function BrwZCM()
	Local aCol := {}

	aAdd(aCol, BrwCol("Item",      "ZCM", "ZCM_ITEM",   "C",  8))
	aAdd(aCol, BrwCol("Interna",   "ZCM", "ZCM_NOIDEN", "C", 16))
	aAdd(aCol, BrwCol("Fraccion",  "ZCM", "ZCM_FRACC",  "C", 14))
	aAdd(aCol, BrwCol("Cant adu",  "ZCM", "ZCM_CANADU", "N", 14))
	aAdd(aCol, BrwCol("Uni adu",   "ZCM", "ZCM_UNIADU", "C",  8))
	aAdd(aCol, BrwCol("Val unit",  "ZCM", "ZCM_VALUNI", "N", 14))
	aAdd(aCol, BrwCol("Val dolar", "ZCM", "ZCM_VALDOL", "N", 14))

	BrwAbre("ZCM", "ZCM_UUID", "Mercancias de comercio exterior", aCol)

Return

// ---------------------------------------------------------------------
Static Function BrwZCL()
	Local aCol := {}

	aAdd(aCol, BrwCol("Item",      "ZCL", "ZCL_ITEM",   "C",  8))
	aAdd(aCol, BrwCol("Tipo rel",  "ZCL", "ZCL_TIPREL", "C",  8))
	aAdd(aCol, BrwCol("UUID relacionado", "ZCL", "ZCL_UUIDRE", "C", 38))

	BrwAbre("ZCL", "ZCL_UUID", "CFDI relacionados", aCol)

Return

// ---------------------------------------------------------------------
// EL BROWSE
//
// El filtro se pone y SE QUITA. Si se queda puesto, la siguiente rutina
// que abra esa tabla -- el Detalle, la exportacion -- ve solo este
// comprobante, y eso se diagnostica muy mal: parece que se perdieron
// datos.
// ---------------------------------------------------------------------
Static Function BrwAbre(cAlias, cCampo, cTitulo, aCol)
	Local oDlg  := NIL
	Local oBrw  := NIL
	Local cUuid := AllTrim(ZCF->ZCF_UUID)
	Local cFil  := ""
	Local nCta  := 0

	If Select(cAlias) == 0
		ChkFile(cAlias)
	EndIf

	If Select(cAlias) == 0
		MsgStop("No se pudo abrir " + cAlias + "." + CRLF + CRLF + ;
			"Si la tabla todavia no existe, corre" + CRLF + ;
			"Herramientas / Construir / 1. Crear tablas.", "ZCFDIBRW")
		Return
	EndIf

	cFil := 'AllTrim(' + cAlias + '->' + cCampo + ') == "' + cUuid + '"'

	(cAlias)->(DbClearFilter())
	(cAlias)->(DbSetFilter(&("{||" + cFil + "}"), cFil))
	(cAlias)->(DbGoTop())

	// Contar antes de abrir: un browse vacio no explica por que esta
	// vacio, y en este proyecto "vacio" casi siempre significa que ese
	// comprobante no trae ese complemento, no que algo fallo.
	Do While !(cAlias)->(Eof())
		nCta++
		(cAlias)->(DbSkip())
	EndDo
	(cAlias)->(DbGoTop())

	If nCta == 0
		(cAlias)->(DbClearFilter())
		MsgInfo("Este comprobante no tiene renglones en " + cAlias + "." + CRLF + CRLF + ;
			"No es una falla: la mayoria de los comprobantes no traen" + CRLF + ;
			"todos los complementos. Un ingreso normal no tiene pagos" + CRLF + ;
			"ni comercio exterior.", "ZCFDIBRW")
		Return
	EndIf

	DEFINE MSDIALOG oDlg TITLE cTitulo + "  --  " + ;
		AllTrim(ZCF->ZCF_SERIE) + " " + AllTrim(ZCF->ZCF_FOLIO) + ;
		"  (" + cValToChar(nCta) + " renglon(es))" ;
		FROM 0, 0 TO 400, 900 PIXEL

	oBrw := FWBrowse():New()
	oBrw:SetOwner(oDlg)

	// SetDataTable va ANTES que SetAlias y no es opcional. Sin el,
	// Activate truena con "Informe el tipo de datos utilizado por la
	// consulta para activar la clase": FWBrowse no asume que la fuente
	// es una tabla, hay que decirselo (tabla, consulta o arreglo).
	oBrw:SetDataTable()
	oBrw:SetAlias(cAlias)
	oBrw:SetColumns(aCol)
	oBrw:DisableConfig()

	// Aqui estuvo un oBrw:SetSeek(.F.) y tronaba con
	//   "argumento #0, parametro bAction error, previsto B->L"
	// SetSeek NO es un interruptor: recibe el BLOQUE que ejecuta la
	// busqueda. Pasarle un logico es darle el tipo equivocado. Como no
	// hace falta buscar en una lista de unos cuantos renglones, se
	// quita en vez de inventarle un bloque.
	oBrw:Activate()

	DEFINE SBUTTON FROM 182, 400 TYPE 1 ACTION oDlg:End() ENABLE OF oDlg

	ACTIVATE MSDIALOG oDlg CENTERED

	(cAlias)->(DbClearFilter())
	(cAlias)->(DbGoTop())

Return

// ---------------------------------------------------------------------
// Una columna. El dato se resuelve por NOMBRE en tiempo de pintado, no
// por posicion al construir: asi un campo que la sesion no ve sale en
// blanco en vez de tirar el browse.
// ---------------------------------------------------------------------
Static Function BrwCol(cTit, cAlias, cCampo, cTipo, nTam)
	Local oCol := FWBrwColumn():New()
	Local cAli := cAlias
	Local cCpo := cCampo

	oCol:SetData({|| BrwDato(cAli, cCpo) })
	oCol:SetTitle(cTit)
	oCol:SetType("C")
	oCol:SetSize(nTam)
	oCol:SetAlign(IIf(cTipo == "C", 0, 1))

Return oCol

// ---------------------------------------------------------------------
// Todo se devuelve como TEXTO, a proposito.
//
// Un numerico pintado por el browse sale con el formato del diccionario,
// que para estas tablas nuevas casi siempre es el de omision y se ve
// mal. Transform aqui le da el mismo formato que ya usan el Detalle y
// la exportacion, y las tres pantallas dicen el mismo numero igual.
// ---------------------------------------------------------------------
Static Function BrwDato(cAlias, cCampo)
	Local nPos := (cAlias)->(FieldPos(cCampo))
	Local xVal := NIL

	If nPos == 0
		Return ""
	EndIf

	xVal := (cAlias)->(FieldGet(nPos))

	Do Case
	Case ValType(xVal) == "N"
		Return AllTrim(Transform(xVal, "@E 999,999,999.99"))
	Case ValType(xVal) == "D"
		Return IIf(Empty(xVal), "", DToC(xVal))
	Case ValType(xVal) == "C" .And. Len(AllTrim(xVal)) == 8 .And. ;
		Right(AllTrim(cCampo), 6) == "FECPAG"
		Return DToC(SToD(AllTrim(xVal)))
	EndCase

Return AllTrim(cValToChar(xVal))
