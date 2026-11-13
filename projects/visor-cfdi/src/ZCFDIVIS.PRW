#INCLUDE "PROTHEUS.CH"
#INCLUDE "TOPCONN.CH"

// El browse abierto, guardado a nivel de archivo para poder refrescarlo
// desde afuera. Lo necesita U_ZCFDIREF: cuando alguien importa un XML
// desde el boton Importar, la lista ya esta armada y no se entera del
// renglon nuevo. Antes se le pedia al usuario cerrar y volver a abrir,
// que es pedirle que compense algo que el programa puede hacer solo.
Static oBrwCfd := NIL

// Si ZCFDICAT esta compilado o no. Se resuelve la primera vez que se
// pide una descripcion de catalogo y ya no se vuelve a preguntar.
//   -1 sin averiguar    1 si esta    0 no esta
Static _nHayCat := -1

// Los criterios del filtro de Buscar.
//
// Viven a nivel de archivo, no dentro de la funcion, porque U_ZCFFIL
// -la que el filtro del alias evalua renglon por renglon- tiene que
// verlos. Es lo que permite que la expresion del filtro sea una simple
// llamada a funcion en vez de una cadena armada a mano: asi las fechas
// se comparan como fechas, el texto se busca en varios campos a la vez,
// y no hay que preocuparse por comillas ni por el tipo con el que la
// sesion este leyendo ZCF_FECHA.
//
//   {desde, hasta, texto, estatus, tipo, origen}
//
// NIL = no hay filtro puesto.
Static _aFil := NIL

/*/{Protheus.doc} ZCFDIVIS
La pantalla del visor: navegar los CFDI cargados.

SOLO LECTURA. Consulta lo que ya esta en ZCF, ZCC, ZCI y ZCP.

QUE DA Y QUE NO

Se usa FWMBrowse, el browse estandar de Protheus, en vez de una
pantalla propia. No es por ortodoxia: de ahi salen gratis el filtro por
columna, la configuracion de columnas, la busqueda y la exportacion a
Excel. Una pantalla hecha a mano tendria que reimplementar todo eso
peor.

Los colores de la leyenda no son adorno: dicen de un vistazo que
comprobantes estan cancelados y de que tipo es cada uno, que es lo
primero que alguien busca al abrir un visor.

EL DETALLE

Del renglon seleccionado se arma una vista con su cabecera, sus
conceptos y sus impuestos en los dos niveles. En esta version se
presenta como texto formateado, que es suficiente para leerlo y
verificar la carga. La cascada de browses anidados viene despues: sin
haber visto los datos reales en pantalla no tiene caso disenarla.

@author Claude + Miguel Yasec
@since 09/2026
/*/
User Function ZCFDIVIS()
	Local oBrw := NIL

	If !VisAbre()
		Return
	EndIf

	// Antes aqui se cortaba y no se abria el visor. Eso tenia sentido
	// cuando importar vivia nada mas en Herramientas; ahora el boton
	// Importar esta AQUI, asi que negar la entrada dejaba al usuario
	// sin forma de llenar lo que esta vacio.
	If ZCF->(LastRec()) == 0
		MsgInfo("El visor esta vacio." + CRLF + CRLF + ;
			"Usa el boton Importar para subir un XML de tu maquina," + CRLF + ;
			"o Herramientas - Construir - Importar todo para cargar" + CRLF + ;
			"lo que hay en el servidor.", "ZCFDIVIS")
	EndIf

	// Se entra siempre con la lista completa. Un filtro que sobrevive
	// de la vez pasada es la forma mas facil de que alguien crea que se
	// le perdieron comprobantes.
	_aFil := NIL
	ZCF->(DbClearFilter())
	ZCF->(DbGoTop())

	oBrw := FWMBrowse():New()
	oBrw:SetAlias("ZCF")
	oBrw:SetDescription("Visor de CFDI")
	oBrw:SetMenuDef("ZCFDIVIS")

	// el orden importa: gana la primera condicion que se cumple, y
	// cancelado manda sobre el tipo de comprobante
	oBrw:AddLegend("AllTrim(ZCF->ZCF_ESTSAT) == 'N'", "BLACK", "El SAT no conoce este folio")
	oBrw:AddLegend("AllTrim(ZCF->ZCF_ESTSAT) == 'C'", "RED", "Cancelado")
	oBrw:AddLegend("AllTrim(ZCF->ZCF_TIPCOM) == 'P'", "BLUE", "Complemento de pago")
	oBrw:AddLegend("AllTrim(ZCF->ZCF_TIPCOM) == 'E'", "YELLOW", "Egreso / nota de credito")
	oBrw:AddLegend("AllTrim(ZCF->ZCF_TIPCOM) == 'T'", "ORANGE", "Traslado")
	oBrw:AddLegend("AllTrim(ZCF->ZCF_TIPCOM) == 'I'", "GREEN", "Ingreso")

	// Las columnas se definen aqui, no en el diccionario. Asi no dependemos
	// de X3_BROWSE ni de que la sesion haya recargado SX3.
	oBrw:SetColumns(VisCols())

	// Se guarda antes de activar: Activate() no devuelve el control
	// hasta que se cierra la ventana, y para entonces ya no sirve.
	oBrwCfd := oBrw

	oBrw:Activate()

	// Al cerrarse, el objeto ya no existe. Dejarlo apuntado seria
	// invitar a que alguien lo refresque cuando ya no hay que refrescar.
	oBrwCfd := NIL

Return

/*/{Protheus.doc} ZCFDIREF
Refresca la lista del visor, si esta abierta.

La llama quien cambia los datos por debajo -- hoy el boton Importar.
Si el visor no esta abierto no hace nada y no se queja: refrescar algo
que no esta en pantalla no es un error, es que no habia que hacerlo.
/*/
User Function ZCFDIREF()

	If oBrwCfd == NIL
		Return .F.
	EndIf

	ZCF->(DbGoTop())
	oBrwCfd:GoTop()
	oBrwCfd:Refresh(.T.)

Return .T.

// ---------------------------------------------------------------------
Static Function MenuDef()
	Local aRot := {}

	// El cuarto elemento es el TIPO de operacion, y no es decorativo:
	// Protheus lo usa para decidir si la accion es legal.
	//
	//   2 = visualizar  necesita un renglon donde pararse
	//   3 = incluir     es lo unico que se puede hacer en tabla vacia
	//
	// Importar tenia 2 y truena con ARQVAZIO en cuanto el visor se queda
	// sin renglones -- que es justo cuando uno mas quiere importar.
	// Ademas 3 es lo que de verdad hace: agrega un comprobante.
	aAdd(aRot, {"Detalle",  "U_ZCFDIDET", 0, 2})

	// Partidas: los renglones que cuelgan de ESTE comprobante, en un
	// browse de verdad -- se pueden ordenar, buscar y copiar, cosa que
	// el Detalle no deja porque es un memo de solo lectura.
	//
	// Es UNA opcion y no una por tabla: el menu ya trae doce, y son
	// todas la misma operacion. ZCFDIBRW pregunta de cual.
	aAdd(aRot, {"Partidas", "U_ZCFDIPAR", 0, 2})
	aAdd(aRot, {"Exportar", "U_ZCFDIEXP", 0, 2})
	aAdd(aRot, {"Importar", "U_ZCFDIUNO", 0, 3})

	// Recargar borra ESTE comprobante y lo vuelve a leer de su xml.
	// Es 2 y no 5 a proposito: pide un renglon donde pararse, pero no
	// es la baja del browse -- la baja y el alta las hace el propio
	// ZCFDIREC, y dejarlo como 5 haria que Protheus intentara borrar
	// por su cuenta el registro que la rutina ya volvio a crear.
	aAdd(aRot, {"Recargar", "U_ZCFDIREC", 0, 2})

	// Ver: filtra la lista entre emitidos y recibidos. Es 3 y no 2 a
	// proposito -- igual que Importar, tiene que poder usarse aunque la
	// lista quede vacia, que es justo lo que pasa al filtrar.
	aAdd(aRot, {"Ver",      "U_ZCFDIORG", 0, 3})

	// PPD: el control de complementos de pago. Tambien es 3 -- no mira
	// el renglon donde estas parado, mira todo el acervo.
	aAdd(aRot, {"PPD",      "U_ZCFDIPP2", 0, 3})

	// Sin sellar: complementos de pago a los que se les genero folio y
	// nunca se termino de timbrar. No salen de ZCF -- no tienen XML,
	// justo por eso quedaron sin sellar. Se le pregunta a SEL.
	aAdd(aRot, {"Sin sellar", "U_ZCFDISE2", 0, 3})

	// PDF: la representacion impresa del comprobante donde estas
	// parado. Es 2 -- necesita un renglon, a diferencia de los dos
	// reportes de arriba, que miran todo el acervo.
	aAdd(aRot, {"PDF",      "U_ZCFDIPD2", 0, 2})

	// Buscar y Totales miran todo el acervo, no el renglon donde estas,
	// asi que van como 3. Buscar ademas TIENE que funcionar con la lista
	// vacia: es justo lo que pasa cuando un filtro no deja nada, y es
	// cuando uno mas necesita poder cambiarlo.
	aAdd(aRot, {"Buscar",   "U_ZCFDIBUS", 0, 3})
	aAdd(aRot, {"Totales",  "U_ZCFDITOT", 0, 3})

	// Nodos: censo de lo que traen los XML, para saber que falta leer.
	// No mira la lista ni el renglon: lee los archivos del servidor.
	aAdd(aRot, {"Nodos",    "U_ZCFDINO2", 0, 3})

	// Buscar nodo: el censo dice en CUANTOS archivos aparece un nodo;
	// este dice en CUALES, y si esos archivos estan timbrados. Sin ese
	// dato no se distingue un nodo que al visor le falta leer de uno
	// que solo vive en borradores sin timbre.
	aAdd(aRot, {"Buscar nodo", "U_ZCFDINO3", 0, 3})

Return aRot

// ---------------------------------------------------------------------
// Detalle del comprobante posicionado.
// ---------------------------------------------------------------------
User Function ZCFDIDET()
	Local cTxt := ""

	If Empty(ZCF->ZCF_UUID)
		MsgStop("No hay un comprobante seleccionado.", "ZCFDIVIS")
		Return
	EndIf

	cTxt := VisCab()
	cTxt += VisCpt()
	cTxt += VisImp()
	cTxt += VisPag()
	cTxt += VisArc()

	VisMues("CFDI " + AllTrim(ZCF->ZCF_SERIE) + " " + ;
		AllTrim(ZCF->ZCF_FOLIO), cTxt)

	// POR QUE SE CAIAN RENGLONES
	//
	// Al volver del Detalle, FWMBrowse repintaba la lista anclandola al
	// registro donde quedo parado el cursor. Todo lo que estaba ARRIBA de
	// ese registro se caia de la vista. Por eso desaparecia un renglon
	// cada vez que se entraba al Detalle, y siempre el de mas arriba --
	// no el que se abrio, que era el que sobrevivia.
	//
	// Los registros nunca se borraron de ZCF. Era la ventana del browse,
	// no los datos.
	//
	// Volver a armar la lista desde el principio es lo unico que la deja
	// completa. Es el mismo trato que ya hace U_ZCFDIREF despues de
	// importar.
	If oBrwCfd != NIL
		ZCF->(DbGoTop())
		oBrwCfd:GoTop()
		oBrwCfd:Refresh(.T.)
	EndIf

Return

// ---------------------------------------------------------------------
Static Function VisCab()
	Local cRet := ""

	cRet := "=== COMPROBANTE ===" + CRLF + CRLF
	cRet += "  Folio fiscal : " + AllTrim(ZCF->ZCF_UUID) + CRLF
	cRet += "  Version      : " + AllTrim(ZCF->ZCF_VERSIO) + ;
		"    Tipo: " + AllTrim(ZCF->ZCF_TIPCOM) + ;
		"  (" + VisTipo(ZCF->ZCF_TIPCOM) + ")" + CRLF
	cRet += "  Serie / folio: " + AllTrim(ZCF->ZCF_SERIE) + ;
		" / " + AllTrim(ZCF->ZCF_FOLIO) + CRLF
	cRet += "  Emision      : " + VisFec("ZCF", "ZCF_FECHA") + ;
		"  " + AllTrim(ZCF->ZCF_HORA) + CRLF
	cRet += "  Timbrado     : " + VisFec("ZCF", "ZCF_FECTIM") + ;
		"  " + AllTrim(ZCF->ZCF_HORTIM) + CRLF
	cRet += "  Estatus SAT  : " + VisEst(ZCF->ZCF_ESTSAT) + CRLF
	cRet += CRLF
	cRet += "  Forma de pago: " + VisCat("c_FormaPago", ZCF->ZCF_FORPAG) + CRLF
	cRet += "  Metodo pago  : " + VisCat("c_MetodoPago", ZCF->ZCF_METPAG) + CRLF
	cRet += "  Condiciones  : " + AllTrim(ZCF->ZCF_CONDPA) + CRLF
	cRet += "  Moneda       : " + AllTrim(ZCF->ZCF_MONEDA) + ;
		"    Tipo de cambio: " + AllTrim(Str(ZCF->ZCF_TIPCAM, 12, 4)) + CRLF
	cRet += "  Exportacion  : " + VisCat("c_Exportacion", ZCF->ZCF_EXPORT) + CRLF
	cRet += CRLF
	cRet += "  Subtotal     : " + VisNum(ZCF->ZCF_SUBTOT) + CRLF
	cRet += "  Descuento    : " + VisNum(ZCF->ZCF_DESCTO) + CRLF
	cRet += "  TOTAL        : " + VisNum(ZCF->ZCF_TOTAL) + CRLF
	cRet += CRLF
	cRet += "  Emisor       : " + AllTrim(ZCF->ZCF_EMIRFC) + ;
		"  " + AllTrim(ZCF->ZCF_EMINOM) + CRLF
	cRet += "     regimen   : " + VisCat("c_RegimenFiscal", ZCF->ZCF_EMIREG) + CRLF
	cRet += "  Receptor     : " + AllTrim(ZCF->ZCF_RECRFC) + ;
		"  " + AllTrim(ZCF->ZCF_RECNOM) + CRLF
	cRet += "     regimen   : " + VisCat("c_RegimenFiscal", ZCF->ZCF_RECREG) + CRLF
	cRet += "     uso CFDI  : " + VisCat("c_UsoCFDI", ZCF->ZCF_USOCFD) + CRLF
	cRet += "     CP        : " + AllTrim(ZCF->ZCF_RECDOM) + CRLF

	// Receptor extranjero: solo se pinta cuando lo hay. Un renglon
	// vacio en todos los comprobantes nacionales seria ruido.
	cRet += VisExtr()
	cRet += CRLF

Return cRet

// ---------------------------------------------------------------------
// Los datos del receptor extranjero, si el comprobante los trae.
//
// Se lee con FieldPos y no directo para que el visor siga abriendo en
// un ambiente donde todavia no se corrio el alta de columnas.
// ---------------------------------------------------------------------
Static Function VisExtr()
	Local cRet := ""
	Local cNrt := VisCpo("ZCF", "ZCF_RECNRT")
	Local cRes := VisCpo("ZCF", "ZCF_RECRES")

	If !Empty(cNrt)
		cRet += "     Reg.ID trib: " + cNrt + CRLF
	EndIf

	If !Empty(cRes)
		cRet += "     Residencia : " + cRes + "   (receptor extranjero)" + CRLF
	EndIf

Return cRet

// ---------------------------------------------------------------------
Static Function VisCpo(cAlias, cCampo)
	Local nPos := (cAlias)->(FieldPos(cCampo))

	If nPos == 0
		Return ""
	EndIf

Return AllTrim(cValToChar((cAlias)->(FieldGet(nPos))))

// ---------------------------------------------------------------------
Static Function VisCpt()
	Local cRet := "=== CONCEPTOS ===" + CRLF + CRLF
	Local nN   := 0

	ZCC->(DbSetOrder(1))
	ZCC->(MsSeek(xFilial("ZCC") + ZCF->ZCF_UUID))

	While !ZCC->(Eof()) .And. ;
		AllTrim(ZCC->ZCC_UUID) == AllTrim(ZCF->ZCF_UUID)

		nN++
		cRet += "  " + AllTrim(ZCC->ZCC_ITEM) + ". " + ;
			AllTrim(ZCC->ZCC_DESCRI) + CRLF
		cRet += "      clave SAT : " + VisCat("c_ClaveProdServ", ZCC->ZCC_CLAVE) + CRLF
		cRet += "      interna   : " + AllTrim(ZCC->ZCC_NOIDEN) + CRLF
		cRet += "      obj.imp   : " + VisCat("c_ObjetoImp", ZCC->ZCC_OBJIMP) + CRLF
		cRet += "      unidad    : " + VisCat("c_ClaveUnidad", ZCC->ZCC_CLAUNI) + CRLF
		cRet += "      " + AllTrim(Str(ZCC->ZCC_CANT, 14, 2)) + " " + ;
			AllTrim(ZCC->ZCC_UNIDAD) + ;
			" x " + VisNum(ZCC->ZCC_VALUNI) + ;
			"  =  " + VisNum(ZCC->ZCC_IMPORT) + CRLF + CRLF

		ZCC->(DbSkip())
	EndDo

	If nN == 0
		cRet += "  (sin conceptos cargados)" + CRLF + CRLF
	EndIf

Return cRet

// ---------------------------------------------------------------------
// LOS IMPUESTOS EN DETALLE
//
// ZCI_NIVEL dice de donde salio cada renglon:
//   C  del concepto        (impuesto federal por renglon)
//   G  del comprobante     (impuesto federal de toda la factura)
//   L  local               (estatal o municipal: ISH y similares)
//
// ZCI_TIPO dice T traslado o R retencion, y significa lo mismo en los
// tres casos.
//
// En el XML, el tipo de factor (_TIPOFACTOR) puede ser "Tasa" o "Cuota".
// Ese valor ya viene en ZCI_TIPFAC. No hay que agregarle prefijo: sale
// duplicado ("Tasa tasa" o "Cuota cuota").
// ---------------------------------------------------------------------
Static Function VisImp()
	Local cRet := "=== IMPUESTOS ===" + CRLF + CRLF
	Local nN   := 0
	Local cTipo := ""
	Local cNiv  := ""

	ZCI->(DbSetOrder(1))
	ZCI->(MsSeek(xFilial("ZCI") + ZCF->ZCF_UUID))

	While !ZCI->(Eof()) .And. ;
		AllTrim(ZCI->ZCI_UUID) == AllTrim(ZCF->ZCF_UUID)

		nN++

		// Nivel: comprobante, concepto, o local (estatal / municipal)
		Do Case
		Case AllTrim(ZCI->ZCI_NIVEL) == "L"
			cNiv := "local"
		Case AllTrim(ZCI->ZCI_NIVEL) == "G"
			cNiv := "comprobante"
		Otherwise
			cNiv := "concepto " + AllTrim(ZCI->ZCI_ITEM)
		EndCase

		// TIPO significa lo mismo en los tres niveles
		cTipo := IIf(AllTrim(ZCI->ZCI_TIPO) == "R", "retencion", "traslado")

		cRet += "  " + cNiv + "   " + cTipo + ;
			"   " + VisTrib(ZCI->ZCI_IMPUES) + CRLF

		If AllTrim(ZCI->ZCI_NIVEL) == "L"
			// El implocal no trae base ni tipo de factor. Imprimir
			// "base 0.00" seria inventar un dato que el XML no dio.
			cRet += "      tasa " + AllTrim(Str(ZCI->ZCI_TASA, 10, 6))
		Else
			cRet += "      base " + VisNum(ZCI->ZCI_BASE)

			// ZCI_TIPFAC ya trae "Tasa" o "Cuota": no lleva prefijo
			If !Empty(AllTrim(ZCI->ZCI_TIPFAC))
				cRet += "   " + AllTrim(ZCI->ZCI_TIPFAC) + ": " + ;
					AllTrim(Str(ZCI->ZCI_TASA, 10, 6))
			EndIf
		EndIf

		cRet += "   importe " + VisNum(ZCI->ZCI_IMPORT) + CRLF

		ZCI->(DbSkip())
	EndDo

	If nN == 0
		cRet += "  (sin impuestos cargados)" + CRLF
	EndIf

Return cRet + CRLF

// ---------------------------------------------------------------------
// Solo para los tipo P: que facturas paga este complemento.
// ---------------------------------------------------------------------
Static Function VisPag()
	Local cRet := ""
	Local nN   := 0

	If AllTrim(ZCF->ZCF_TIPCOM) != "P"
		Return ""
	EndIf

	cRet := "=== DOCUMENTOS QUE PAGA ===" + CRLF + CRLF

	ZCP->(DbSetOrder(1))
	ZCP->(MsSeek(xFilial("ZCP") + ZCF->ZCF_UUID))

	While !ZCP->(Eof()) .And. ;
		AllTrim(ZCP->ZCP_UUID) == AllTrim(ZCF->ZCF_UUID)

		nN++
		cRet += "  " + AllTrim(ZCP->ZCP_SERIE) + " " + ;
			AllTrim(ZCP->ZCP_FOLIO) + ;
			"   parcialidad " + AllTrim(ZCP->ZCP_PARCIA) + CRLF
		cRet += "      pagado el " + VisFec("ZCP", "ZCP_FECPAG") + CRLF
		cRet += "      forma     " + VisCat("c_FormaPago", ZCP->ZCP_FORPAG) + CRLF
		cRet += "      saldo anterior " + VisNum(ZCP->ZCP_SALANT) + ;
			"  pagado " + VisNum(ZCP->ZCP_SALPAG) + ;
			"  insoluto " + VisNum(ZCP->ZCP_SALINS) + CRLF
		cRet += "      UUID " + AllTrim(ZCP->ZCP_UUIDRE) + CRLF + CRLF

		ZCP->(DbSkip())
	EndDo

	If nN == 0
		cRet += "  (el complemento no trae documentos relacionados)" + CRLF + CRLF
	EndIf

Return cRet

// ---------------------------------------------------------------------
Static Function VisArc()
	Local cRet := "=== ORIGEN ===" + CRLF + CRLF

	cRet += "  Archivo   : " + AllTrim(ZCF->ZCF_ARCHIV) + CRLF
	cRet += "  Carpeta   : " + AllTrim(ZCF->ZCF_RUTA) + CRLF
	cRet += "  Especie   : " + AllTrim(ZCF->ZCF_ESPECI) + CRLF
	cRet += "  Importado : " + VisFec("ZCF", "ZCF_FECIMP") + CRLF

Return cRet

// =====================================================================
// APOYO
// =====================================================================

// ---------------------------------------------------------------------
// Columnas del browse, armadas a mano.
// ---------------------------------------------------------------------
Static Function VisCols()
	Local aRet := {}

	AAdd(aRet, VisCol("Serie",     {|| ZCF->ZCF_SERIE                    }, "C", 10))
	AAdd(aRet, VisCol("Folio",     {|| ZCF->ZCF_FOLIO                    }, "C", 15))
	AAdd(aRet, VisCol("Fecha",     {|| VisFec("ZCF", "ZCF_FECHA")        }, "C", 10))
	AAdd(aRet, VisCol("Tipo",      {|| VisTipo(ZCF->ZCF_TIPCOM)          }, "C", 10))
	AAdd(aRet, VisCol("Origen",    {|| VisOrig(ZCF->ZCF_ORIGEN)          }, "C", 14))

	// El emisor faltaba, y en un acervo de comprobantes RECIBIDOS es la
	// primera columna que alguien busca: de quien es esta factura.
	AAdd(aRet, VisCol("RFC emisor",{|| ZCF->ZCF_EMIRFC                   }, "C", 14))
	AAdd(aRet, VisCol("Emisor",    {|| ZCF->ZCF_EMINOM                   }, "C", 40))

	AAdd(aRet, VisCol("RFC recep", {|| ZCF->ZCF_RECRFC                   }, "C", 14))
	AAdd(aRet, VisCol("Receptor",  {|| ZCF->ZCF_RECNOM                   }, "C", 40))

	// Metodo y forma de pago con su descripcion del catalogo del SAT.
	// "PPD" no le dice nada a nadie; "Pago en parcialidades o diferido"
	// si, y es justo lo que se filtra para revisar complementos.
	AAdd(aRet, VisCol("Met.pago",  {|| VisCat("c_MetodoPago", ZCF->ZCF_METPAG) }, "C", 36))
	AAdd(aRet, VisCol("Forma pago",{|| VisCat("c_FormaPago",  ZCF->ZCF_FORPAG) }, "C", 40))

	AAdd(aRet, VisCol("Moneda",    {|| ZCF->ZCF_MONEDA                   }, "C",  6))
	AAdd(aRet, VisCol("Total",     {|| VisNum(ZCF->ZCF_TOTAL)            }, "C", 15))
	AAdd(aRet, VisCol("Estatus",   {|| VisEst(ZCF->ZCF_ESTSAT)           }, "C", 45))
	AAdd(aRet, VisCol("Folio fiscal", {|| ZCF->ZCF_UUID                  }, "C", 38))

Return aRet

// ---------------------------------------------------------------------
// CLAVE + DESCRIPCION, tomada del catalogo del SAT.
//
//   VisCat("c_FormaPago", "03")  ->  "03 - Transferencia electronica..."
//
// Tres cosas que tiene que aguantar sin quejarse:
//
//   1. Que ZCFDICAT no este compilado todavia. Por eso FindFunction:
//      si no esta, se devuelve la clave sola y el visor sigue vivo.
//   2. Que el catalogo no se haya cargado. Eso lo resuelve U_ZCATDES,
//      que devuelve la clave cuando no encuentra la descripcion.
//   3. Que la clave venga vacia -- pasa seguido, los campos opcionales
//      del XML llegan vacios. Ahi no se inventa nada.
// ---------------------------------------------------------------------
Static Function VisCat(cCat, cClave)
	Local cCla := AllTrim(cValToChar(cClave))
	Local cDes := ""

	If Empty(cCla)
		Return ""
	EndIf

	// FindFunction se pregunta UNA vez por sesion, no por renglon: el
	// browse repinta miles de veces y esta llamada no es gratis.
	// -1 = todavia no se ha preguntado, 1 = si esta, 0 = no esta.
	If _nHayCat == -1
		_nHayCat := IIf(FindFunction("U_ZCATDES"), 1, 0)
	EndIf

	If _nHayCat == 0
		Return cCla
	EndIf

	cDes := U_ZCATDES(cCat, cCla)

	// Si la descripcion es la clave misma, no se pone dos veces.
	If AllTrim(cDes) == cCla .Or. Empty(cDes)
		Return cCla
	EndIf

Return cCla + " - " + AllTrim(cDes)

/*/{Protheus.doc} ZCFDINO2
Llama al censo de nodos, si esta compilado.
/*/
User Function ZCFDINO2()

	If FindFunction("U_ZCFDINOD")
		U_ZCFDINOD()
	Else
		MsgStop("Falta compilar ZCFDINOD.PRW.", "ZCFDIVIS")
	EndIf

Return

/*/{Protheus.doc} ZCFDINO3
Lista que archivos XML contienen un nodo o atributo, y si traen timbre.
/*/
User Function ZCFDINO3()

	If FindFunction("U_ZCFDINOF")
		U_ZCFDINOF()
	Else
		MsgStop("Falta compilar ZCFDINOD.PRW.", "ZCFDIVIS")
	EndIf

Return

/*/{Protheus.doc} ZCFDIPD2
Abre el PDF del comprobante, si ZCFDIPDF esta compilado.
/*/
User Function ZCFDIPD2()

	If FindFunction("U_ZCFDIPDF")
		U_ZCFDIPDF()
	Else
		MsgStop("Falta compilar ZCFDIPDF.PRW.", "ZCFDIVIS")
	EndIf

Return

/*/{Protheus.doc} ZCFDISE2
Llama al reporte de complementos sin sellar, si esta compilado.
/*/
User Function ZCFDISE2()

	If FindFunction("U_ZCFDISEL")
		U_ZCFDISEL()
	Else
		MsgStop("Falta compilar ZCFDISEL.PRW.", "ZCFDIVIS")
	EndIf

Return

/*/{Protheus.doc} ZCFDIPP2
Llama al control de facturas PPD, si esta compilado.

Va envuelto y no se llama directo desde MenuDef porque una opcion de
menu que apunta a una funcion inexistente truena al pulsarla, sin decir
por que. Asi al menos se dice que falta compilar.
/*/
User Function ZCFDIPP2()

	If FindFunction("U_ZCFDIPPD")
		U_ZCFDIPPD()
	Else
		MsgStop("Falta compilar ZCFDIPPD.PRW.", "ZCFDIVIS")
	EndIf

Return

/*/{Protheus.doc} ZCFDIORG
Filtra el visor entre emitidos, recibidos y todos.

El filtro se pone sobre el ALIAS, no sobre el browse. FWMBrowse recorre
ZCF, asi que un DbSetFilter le llega igual y no depende de que version
del framework tenga este ambiente.
/*/
User Function ZCFDIORG()
	Local nOpc := 0

	// Si nadie ha calculado el origen, filtrar no sirve de nada: todo
	// caeria del mismo lado. Mejor decirlo y ofrecer arreglarlo.
	If !VisHayOr()
		Return
	EndIf

	nOpc := Aviso("Que se quiere ver", ;
		"Emitidos son los que facturamos nosotros. Recibidos los de proveedores." + CRLF + CRLF + ;
		"Se decide por el RFC del emisor." + CRLF + ;
		"Todos quita el filtro y devuelve la lista completa.", ;
		{"Todos", "Emitidos", "Recibidos"})

	Do Case
	Case nOpc == 1
		ZCF->(DbClearFilter())
	Case nOpc == 2
		ZCF->(DbSetFilter({|| AllTrim(ZCF->ZCF_ORIGEN) == "E" }, ;
			'AllTrim(ZCF->ZCF_ORIGEN) == "E"'))
	Case nOpc == 3
		ZCF->(DbSetFilter({|| AllTrim(ZCF->ZCF_ORIGEN) == "R" }, ;
			'AllTrim(ZCF->ZCF_ORIGEN) == "R"'))
	Otherwise
		Return
	EndCase

	ZCF->(DbGoTop())

	If oBrwCfd != NIL
		oBrwCfd:GoTop()
		oBrwCfd:Refresh(.T.)
	EndIf

Return

// ---------------------------------------------------------------------
// Avisa si el origen todavia no se ha calculado.
//
// Se revisa de verdad, recorriendo la tabla, en vez de confiar en el
// primer renglon: un acervo donde todo es "E" puede ser un acervo bien
// calculado de puros emitidos, o uno que nadie ha tocado. La diferencia
// esta en si hay algun "?" o si el campo viene vacio.
// ---------------------------------------------------------------------
Static Function VisHayOr()
	Local lOk  := .F.
	Local nRec := ZCF->(Recno())
	Local cFil := ZCF->(DbFilter())

	ZCF->(DbClearFilter())
	ZCF->(DbGoTop())

	While !ZCF->(Eof())
		If AllTrim(ZCF->ZCF_ORIGEN) == "R"
			lOk := .T.
			Exit
		EndIf
		ZCF->(DbSkip())
	EndDo

	If !Empty(cFil)
		ZCF->(DbSetFilter({|| &(cFil) }, cFil))
	EndIf
	ZCF->(DbGoTo(nRec))

	// No haber encontrado un solo recibido no prueba que este mal, pero
	// en un acervo real es rarisimo. Vale la pena preguntar.
	If !lOk
		If MsgYesNo("No hay ningun comprobante marcado como RECIBIDO." + CRLF + CRLF + ;
			"Los comprobantes importados antes de esta version quedaron" + CRLF + ;
			"marcados como emitidos sin comprobarlo, asi que lo mas" + CRLF + ;
			"probable es que el origen nunca se haya calculado." + CRLF + CRLF + ;
			"CALCULARLO AHORA?", "ZCFDIVIS")

			If FindFunction("U_ZCFDIORI")
				U_ZCFDIORI()
				If oBrwCfd != NIL
					ZCF->(DbGoTop())
					oBrwCfd:GoTop()
					oBrwCfd:Refresh(.T.)
				EndIf
			Else
				MsgStop("Falta compilar ZCFDIIMP.PRW.", "ZCFDIVIS")
			EndIf
		EndIf
		Return .F.
	EndIf

Return .T.

// ---------------------------------------------------------------------
// "?" y el campo vacio se distinguen a proposito: uno quiere decir que
// se intento y no se pudo, el otro que nunca se intento.
// ---------------------------------------------------------------------
Static Function VisOrig(cOri)
	Local cRet := ""

	Do Case
	Case AllTrim(cOri) == "E" ; cRet := "emitido"
	Case AllTrim(cOri) == "R" ; cRet := "RECIBIDO"
	Case AllTrim(cOri) == "?" ; cRet := "?"
	Otherwise                 ; cRet := "sin calcular"
	EndCase

Return cRet

/*/{Protheus.doc} ZCFDIBUS
Filtra la lista por fecha, texto, estatus, tipo y origen.

POR QUE UNA FUNCION Y NO UNA CADENA

DbSetFilter recibe un bloque de codigo y, aparte, la MISMA condicion
escrita como texto -- Protheus usa esa cadena cuando necesita volver a
armar el filtro por su cuenta. Armar esa cadena concatenando valores
obliga a meter comillas, a formatear fechas a mano y a rezar para que
ningun nombre de cliente traiga un apostrofe.

Aqui la condicion es siempre la misma: "U_ZCFFIL()". Los criterios van
por una estatica del archivo. La cadena nunca cambia, no lleva datos
adentro, y no hay nada que escapar.

Ademas permite comparar fechas como fechas aunque la sesion este leyendo
ZCF_FECHA como texto de 8 caracteres, que pasa cuando las tablas se
acaban de crear.
/*/
User Function ZCFDIBUS()
	Local dDe  := CToD("")
	Local dA   := CToD("")
	Local cTx  := Space(40)
	Local cEst := "Todos"
	Local cTip := "Todos"
	Local cOri := "Todos"
	Local lOk  := .F.
	Local nN   := 0
	Local nMan := 0

	// Etiquetas y claves, en el mismo orden. La primera es "Todos" = ""
	Local aEst := {"Todos", "Vigente", "Cancelado", "El SAT no lo conoce", "Sin consultar"}
	Local kEst := {"",      "V",       "C",         "N",                   "?"            }

	Local aTip := {"Todos", "Ingreso", "Egreso", "Traslado", "Nomina", "Pago"}
	Local kTip := {"",      "I",       "E",      "T",        "N",      "P"   }

	Local aOri := {"Todos", "Emitido", "Recibido"}
	Local kOri := {"",      "E",       "R"        }

	Local oDlg, oG1, oG2, oG3, oC1, oC2, oC3

	If Select("ZCF") == 0
		MsgStop("El visor no esta abierto.", "ZCFDIVIS")
		Return
	EndIf

	// Si ya hay un filtro puesto, la ventana se abre con lo que se
	// escribio la vez pasada. Afinar una busqueda es lo normal;
	// obligar a recapturar todo cada vez, no.
	If _aFil != NIL
		dDe  := _aFil[1]
		dA   := _aFil[2]
		cTx  := PadR(_aFil[3], 40)
		cEst := VisEtiq(aEst, kEst, _aFil[4])
		cTip := VisEtiq(aTip, kTip, _aFil[5])
		cOri := VisEtiq(aOri, kOri, _aFil[6])
	EndIf

	DEFINE MSDIALOG oDlg TITLE "Buscar en el visor" FROM 0, 0 TO 250, 460 PIXEL

	@ 010, 010 SAY "Fecha desde" SIZE 45, 8 OF oDlg PIXEL
	@ 008, 060 MSGET oG1 VAR dDe  SIZE 50, 9 OF oDlg PIXEL

	@ 010, 125 SAY "hasta" SIZE 25, 8 OF oDlg PIXEL
	@ 008, 150 MSGET oG2 VAR dA   SIZE 50, 9 OF oDlg PIXEL

	@ 028, 010 SAY "Texto" SIZE 45, 8 OF oDlg PIXEL
	@ 026, 060 MSGET oG3 VAR cTx  SIZE 140, 9 OF oDlg PIXEL

	@ 040, 060 SAY "Busca en RFC, nombre, serie, folio y folio fiscal." ;
		SIZE 160, 8 OF oDlg PIXEL

	@ 058, 010 SAY "Estatus SAT" SIZE 45, 8 OF oDlg PIXEL
	@ 056, 060 MSCOMBOBOX oC1 VAR cEst ITEMS aEst SIZE 100, 10 OF oDlg PIXEL

	@ 076, 010 SAY "Tipo" SIZE 45, 8 OF oDlg PIXEL
	@ 074, 060 MSCOMBOBOX oC2 VAR cTip ITEMS aTip SIZE 100, 10 OF oDlg PIXEL

	@ 094, 010 SAY "Origen" SIZE 45, 8 OF oDlg PIXEL
	@ 092, 060 MSCOMBOBOX oC3 VAR cOri ITEMS aOri SIZE 100, 10 OF oDlg PIXEL

	// Quitar filtro es una tercera salida, no "aceptar con todo en
	// blanco": deja explicito como volver a ver todo.
	DEFINE SBUTTON FROM 110, 130 TYPE 1 ACTION (lOk := .T., oDlg:End()) ENABLE OF oDlg
	DEFINE SBUTTON FROM 110, 165 TYPE 2 ACTION oDlg:End() ENABLE OF oDlg

	@ 111, 010 BUTTON "Quitar filtro" SIZE 50, 12 OF oDlg PIXEL ;
		ACTION (lOk := .F., _aFil := NIL, oDlg:End())

	ACTIVATE MSDIALOG oDlg CENTERED

	If lOk
		// SE LEE LA POSICION DEL COMBO, NO SU VARIABLE
		//
		// La primera version confiaba en la variable que el MSCOMBOBOX
		// tiene asociada. No funciono: los MSGET si escriben de vuelta
		// en su variable, pero los combos de este ambiente no -- se
		// quedaban en "Todos" por mas que se eligiera otra cosa, y
		// "Todos" es no filtrar. El sintoma era desconcertante: elegias
		// Ingreso y te devolvia los 66, como si no hubieras filtrado.
		//
		// El objeto del combo si conserva la seleccion en :nAt, y sigue
		// vivo despues de que la ventana se cierra. VisIdx usa la
		// variable cuando coincide con alguna etiqueta y se va a :nAt
		// cuando no, asi funciona de las dos formas.
		_aFil := {dDe, dA, AllTrim(cTx), ;
		          VisKey(kEst, VisIdx(aEst, cEst, oC1)), ;
		          VisKey(kTip, VisIdx(aTip, cTip, oC2)), ;
		          VisKey(kOri, VisIdx(aOri, cOri, oC3))}
	EndIf

	If _aFil == NIL
		ZCF->(DbClearFilter())
	Else
		ZCF->(DbSetFilter({|| U_ZCFFIL() }, "U_ZCFFIL()"))
	EndIf

	ZCF->(DbGoTop())

	If oBrwCfd != NIL
		oBrwCfd:GoTop()
		oBrwCfd:Refresh(.T.)
	EndIf

	nN := VisCuant()

	If _aFil != NIL .And. nN == 0

		// LA LISTA QUEDO VACIA: HAY QUE SABER POR QUE
		//
		// Dos causas posibles y muy distintas:
		//
		//   1. De verdad ningun comprobante cumple. Normal.
		//   2. El filtro del alias se lo comio. El RDD de TOPCONN
		//      intenta traducir la condicion a SQL para que la resuelva
		//      la base; si no puede, hay versiones que devuelven cero
		//      renglones en vez de resolverla en ADVPL.
		//
		// Desde afuera las dos se ven igual: una lista vacia. Asi que
		// se cuenta otra vez SIN filtro, evaluando la condicion a mano.
		// Si a mano salen mas de cero, la condicion estaba bien y quien
		// se comio los renglones fue el filtro.
		nMan := VisAMano()

		If nMan > 0
			MsgStop("EL FILTRO NO ESTA FUNCIONANDO" + CRLF + CRLF + ;
				"Evaluando la condicion a mano salen " + cValToChar(nMan) + ;
				" comprobante(s)," + CRLF + ;
				"pero con el filtro puesto la lista queda vacia." + CRLF + CRLF + ;
				"O sea que la condicion esta bien y el problema es el" + CRLF + ;
				"filtro del alias: el RDD no la esta resolviendo." + CRLF + CRLF + ;
				"Se quito el filtro para que no te quedes sin lista." + CRLF + ;
				"Pasame esta pantalla y lo corrijo.", "ZCFDIVIS")

			// No se deja al usuario con una lista vacia por un problema
			// que no es suyo.
			_aFil := NIL
			ZCF->(DbClearFilter())
			ZCF->(DbGoTop())
			If oBrwCfd != NIL
				oBrwCfd:GoTop()
				oBrwCfd:Refresh(.T.)
			EndIf
		Else
			MsgInfo("Ningun comprobante cumple con eso." + CRLF + CRLF + ;
				"La lista quedo vacia. Vuelve a Buscar y afloja algun" + CRLF + ;
				"criterio, o usa Quitar filtro.", "ZCFDIVIS")
		EndIf

	Else
		// Se dice QUE filtro se entendio, no solo cuantos salieron. Si
		// el programa entiende algo distinto de lo que se eligio, asi
		// se ve de inmediato en vez de quedar en "que raro, salieron
		// mas de los que esperaba".
		MsgInfo(IIf(_aFil == NIL, "Filtro quitado." + CRLF + CRLF, ;
			VisDice() + CRLF) + ;
			"Se estan mostrando " + cValToChar(nN) + " comprobante(s).", "ZCFDIVIS")
	EndIf

Return

/*/{Protheus.doc} ZCFFIL
Dice si el renglon donde esta ZCF cumple con el filtro.

La evalua el propio alias, un renglon a la vez. Tiene que ser User
Function -- y no Static- porque Protheus a veces vuelve a armar el
filtro a partir de la cadena "U_ZCFFIL()", y una macro no alcanza a ver
las funciones estaticas de este fuente.
/*/
User Function ZCFFIL()
	Local dFec := CToD("")
	Local cTx  := ""

	If _aFil == NIL
		Return .T.
	EndIf

	// --- fechas ---
	If !Empty(_aFil[1]) .Or. !Empty(_aFil[2])
		dFec := VisFecD("ZCF", "ZCF_FECHA")
		If Empty(dFec)
			Return .F.
		EndIf
		If !Empty(_aFil[1]) .And. dFec < _aFil[1]
			Return .F.
		EndIf
		If !Empty(_aFil[2]) .And. dFec > _aFil[2]
			Return .F.
		EndIf
	EndIf

	// --- texto, en cualquiera de los campos donde uno lo buscaria ---
	If !Empty(_aFil[3])
		cTx := Upper(AllTrim(_aFil[3]))
		If !(cTx $ Upper(ZCF->ZCF_EMIRFC)) .And. ;
		   !(cTx $ Upper(ZCF->ZCF_EMINOM)) .And. ;
		   !(cTx $ Upper(ZCF->ZCF_RECRFC)) .And. ;
		   !(cTx $ Upper(ZCF->ZCF_RECNOM)) .And. ;
		   !(cTx $ Upper(ZCF->ZCF_SERIE))  .And. ;
		   !(cTx $ Upper(ZCF->ZCF_FOLIO))  .And. ;
		   !(cTx $ Upper(ZCF->ZCF_UUID))
			Return .F.
		EndIf
	EndIf

	// --- estatus, tipo, origen ---
	If !Empty(_aFil[4]) .And. AllTrim(ZCF->ZCF_ESTSAT) != _aFil[4]
		Return .F.
	EndIf

	If !Empty(_aFil[5]) .And. AllTrim(ZCF->ZCF_TIPCOM) != _aFil[5]
		Return .F.
	EndIf

	If !Empty(_aFil[6]) .And. AllTrim(ZCF->ZCF_ORIGEN) != _aFil[6]
		Return .F.
	EndIf

Return .T.

/*/{Protheus.doc} ZCFDITOT
Suma lo que hay en la lista, respetando el filtro puesto.

FWMBrowse no tiene pie de pagina donde poner esto, asi que va en su
propia ventana. Es la unica diferencia con el de CONTPAQi: ahi los
totales estan siempre a la vista y aqui hay que pedirlos.

LOS IMPUESTOS SALEN DE LA ARITMETICA DEL PROPIO CFDI

  impuestos = total - (subtotal - descuento)

No se suma ZCI. Podria parecer mas directo, pero ZCI guarda el mismo
impuesto en tres niveles -comprobante, grupo y linea- y sumarlos sin
cuidado cuenta lo mismo dos o tres veces. La resta de arriba sale de los
totales que el propio comprobante declara y no se puede doble contar.

Es el impuesto NETO: si un comprobante trae retenciones, ya vienen
restadas ahi. No es lo mismo que el IVA trasladado.
/*/
User Function ZCFDITOT()
	Local cTxt := ""
	Local nRec := 0
	Local nN   := 0
	Local nSub := 0
	Local nDes := 0
	Local nTot := 0
	Local aTip := {0, 0, 0, 0, 0, 0}
	Local aEst := {0, 0, 0, 0}
	Local nEmi := 0
	Local nRcb := 0
	Local cT   := ""
	Local cE   := ""

	If Select("ZCF") == 0
		MsgStop("El visor no esta abierto.", "ZCFDIVIS")
		Return
	EndIf

	nRec := ZCF->(Recno())
	ZCF->(DbGoTop())

	Do While !ZCF->(Eof())
		nN++
		nSub += ZCF->ZCF_SUBTOT
		nDes += ZCF->ZCF_DESCTO
		nTot += ZCF->ZCF_TOTAL

		cT := AllTrim(ZCF->ZCF_TIPCOM)
		Do Case
		Case cT == "I" ; aTip[1]++
		Case cT == "E" ; aTip[2]++
		Case cT == "T" ; aTip[3]++
		Case cT == "N" ; aTip[4]++
		Case cT == "P" ; aTip[5]++
		Otherwise      ; aTip[6]++
		EndCase

		cE := AllTrim(ZCF->ZCF_ESTSAT)
		Do Case
		Case cE == "V" ; aEst[1]++
		Case cE == "C" ; aEst[2]++
		Case cE == "N" ; aEst[3]++
		Otherwise      ; aEst[4]++
		EndCase

		Do Case
		Case AllTrim(ZCF->ZCF_ORIGEN) == "E" ; nEmi++
		Case AllTrim(ZCF->ZCF_ORIGEN) == "R" ; nRcb++
		EndCase

		ZCF->(DbSkip())
	EndDo

	ZCF->(DbGoTo(nRec))

	cTxt += IIf(_aFil == NIL, ;
		"=== TODO EL VISOR ===", ;
		"=== SOLO LO QUE EL FILTRO DEJA VER ===") + CRLF + CRLF

	If _aFil != NIL
		cTxt += VisDice() + CRLF
	EndIf

	cTxt += "  Comprobantes : " + Str(nN, 8) + CRLF + CRLF

	cTxt += "  Subtotal     : " + PadL(VisMto(nSub), 18) + CRLF
	cTxt += "  Descuento    : " + PadL(VisMto(nDes), 18) + CRLF
	cTxt += "  Impuestos    : " + PadL(VisMto(nTot - (nSub - nDes)), 18) + ;
		"   (neto)" + CRLF
	cTxt += "  TOTAL        : " + PadL(VisMto(nTot), 18) + CRLF + CRLF

	cTxt += "  CUIDADO AL SUMAR" + CRLF + CRLF
	cTxt += "  Estos totales mezclan tipos de comprobante y monedas." + CRLF
	cTxt += "  Un egreso resta y aqui suma; un comprobante en dolares" + CRLF
	cTxt += "  entra con su valor nominal, sin convertir. Para un dato" + CRLF
	cTxt += "  contable hay que filtrar primero por tipo y por moneda." + CRLF + CRLF

	cTxt += "=== POR TIPO ===" + CRLF + CRLF
	cTxt += "  Ingreso      : " + Str(aTip[1], 8) + CRLF
	cTxt += "  Egreso       : " + Str(aTip[2], 8) + CRLF
	cTxt += "  Traslado     : " + Str(aTip[3], 8) + CRLF
	cTxt += "  Nomina       : " + Str(aTip[4], 8) + CRLF
	cTxt += "  Pago         : " + Str(aTip[5], 8) + CRLF
	If aTip[6] > 0
		cTxt += "  Otro         : " + Str(aTip[6], 8) + CRLF
	EndIf
	cTxt += CRLF

	cTxt += "=== POR ESTATUS ANTE EL SAT ===" + CRLF + CRLF
	cTxt += "  Vigente      : " + Str(aEst[1], 8) + CRLF
	cTxt += "  Cancelado    : " + Str(aEst[2], 8) + CRLF
	cTxt += "  No lo conoce : " + Str(aEst[3], 8) + CRLF
	cTxt += "  Sin consultar: " + Str(aEst[4], 8) + ;
		IIf(aEst[4] > 0, "   <- a estos no se les ha preguntado", "") + CRLF + CRLF

	cTxt += "=== POR ORIGEN ===" + CRLF + CRLF
	cTxt += "  Emitido      : " + Str(nEmi, 8) + CRLF
	cTxt += "  Recibido     : " + Str(nRcb, 8) + CRLF

	VisMues("Totales", cTxt)

Return

// ---------------------------------------------------------------------
// El filtro puesto, en palabras. Para que los totales digan de que son.
// ---------------------------------------------------------------------
Static Function VisDice()
	Local cRet := "  Filtro: "

	If !Empty(_aFil[1])
		cRet += "desde " + DToC(_aFil[1]) + "  "
	EndIf
	If !Empty(_aFil[2])
		cRet += "hasta " + DToC(_aFil[2]) + "  "
	EndIf
	If !Empty(_aFil[3])
		cRet += "texto '" + _aFil[3] + "'  "
	EndIf
	If !Empty(_aFil[4])
		cRet += "estatus " + _aFil[4] + "  "
	EndIf
	If !Empty(_aFil[5])
		cRet += "tipo " + _aFil[5] + "  "
	EndIf
	If !Empty(_aFil[6])
		cRet += "origen " + _aFil[6] + "  "
	EndIf

Return cRet + CRLF

// ---------------------------------------------------------------------
// Cuantos renglones deja ver el filtro. Se cuenta recorriendo, no con
// LastRec(): LastRec cuenta lo que hay en la tabla, no lo que el filtro
// deja pasar, y seria justo el numero que no se quiere.
// ---------------------------------------------------------------------
Static Function VisCuant()
	Local nRec := ZCF->(Recno())
	Local nN   := 0

	ZCF->(DbGoTop())
	Do While !ZCF->(Eof())
		nN++
		ZCF->(DbSkip())
	EndDo

	ZCF->(DbGoTo(nRec))
	ZCF->(DbGoTop())

Return nN

// ---------------------------------------------------------------------
// Cuenta a mano: sin filtro de alias, evaluando U_ZCFFIL renglon por
// renglon. Es el numero que dice si la condicion sirve.
// ---------------------------------------------------------------------
Static Function VisAMano()
	Local cFil := ZCF->(DbFilter())
	Local nRec := ZCF->(Recno())
	Local nN   := 0

	ZCF->(DbClearFilter())
	ZCF->(DbGoTop())

	Do While !ZCF->(Eof())
		If U_ZCFFIL()
			nN++
		EndIf
		ZCF->(DbSkip())
	EndDo

	// Se deja como estaba: quien llamo decide que hacer con el dato.
	If !Empty(cFil)
		ZCF->(DbSetFilter({|| U_ZCFFIL() }, cFil))
	EndIf
	ZCF->(DbGoTo(nRec))

Return nN

// ---------------------------------------------------------------------
// La etiqueta del combo <-> la clave que se guarda.
//
// Los combos trabajan con el texto que ve el usuario; el filtro compara
// contra la letra que trae el campo. Las dos listas van juntas y en el
// mismo orden -- etiquetas y claves- y estas dos funciones traducen de
// una a otra por posicion.
//
// Se pasan las dos listas como parametro en vez de tenerlas aqui
// adentro: asi la lista de estatus se escribe UNA vez, donde se arma el
// dialogo, y no hay forma de que las dos copias se desincronicen.
//
// La posicion 1 es "Todos" en los tres, y su clave es "" -- o sea, no
// filtrar por ese campo.
// ---------------------------------------------------------------------
// La posicion elegida en el combo.
//
// Primero por la etiqueta, que es lo directo cuando la variable si se
// actualizo. Si no coincide con ninguna, se le pregunta al objeto: :nAt
// trae la posicion seleccionada y sobrevive al cierre de la ventana.
//
// Se compara con AllTrim por si el control devuelve la etiqueta con
// espacios de relleno.
Static Function VisIdx(aEtiq, cEtiq, oCbo)
	Local nPos := aScan(aEtiq, {|x| AllTrim(x) == AllTrim(cValToChar(cEtiq)) })

	If nPos > 0
		Return nPos
	EndIf

	If ValType(oCbo) == "O"
		nPos := oCbo:nAt
		If nPos >= 1 .And. nPos <= Len(aEtiq)
			Return nPos
		EndIf
	EndIf

	// Sin forma de saberlo, se asume "Todos": mostrar de mas es menos
	// danino que esconder comprobantes por un control que no contesto.
Return 1

// ---------------------------------------------------------------------
Static Function VisKey(aClav, nPos)

	If nPos < 1 .Or. nPos > Len(aClav)
		Return ""
	EndIf

Return aClav[nPos]

// ---------------------------------------------------------------------
Static Function VisEtiq(aEtiq, aClav, cClave)
	Local nPos := aScan(aClav, {|x| x == cClave })

	If nPos < 1 .Or. nPos > Len(aEtiq)
		Return aEtiq[1]
	EndIf

Return aEtiq[nPos]

// ---------------------------------------------------------------------
// La fecha como FECHA, venga como venga.
//
// VisFec devuelve texto para pintarlo en pantalla. Para comparar contra
// un rango hace falta el tipo fecha de verdad, y el campo puede estar
// leyendose como D o como C(8) segun si la sesion ya recargo el
// diccionario. Misma historia que en el resto del paquete.
// ---------------------------------------------------------------------
Static Function VisFecD(cAlias, cCampo)
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
// Un importe alineado, con separador de miles.
// ---------------------------------------------------------------------
Static Function VisMto(nVal)
Return AllTrim(Transform(nVal, "@E 999,999,999.99"))

// ---------------------------------------------------------------------
Static Function VisCol(cTit, bDado, cTipo, nTam)
	Local oCol := FWBrwColumn():New()

	oCol:SetData(bDado)
	oCol:SetTitle(cTit)
	oCol:SetType(cTipo)
	oCol:SetSize(nTam)
	oCol:SetAlign(IIf(cTipo == "C", 0, 1))

Return oCol

// ---------------------------------------------------------------------
// Una fecha puede venir como fecha o como texto AAAAMMDD, segun si la
// sesion ya recargo el diccionario. Se lee de las dos formas.
// ---------------------------------------------------------------------
Static Function VisFec(cAlias, cCampo)
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

// =====================================================================
// MOSTRAR UN NUMERO EN FORMATO AMIGABLE
//
// NOTA IMPORTANTE SOBRE VALORES NULOS:
//
// En el XML, cuando un campo es opcional (tipo de cambio, descuento,
// etc.), el atributo simplemente se omite. Ejemplo: sin tipo de cambio,
// el XML no tiene _TIPOCAMBIO.
//
// El parser lee "atributo ausente" como cadena vacia "", que ImpNum()
// convierte a 0. Protheus no permite NIL en numerico, asi que queda
// guardado como 0.00.
//
// Eso significa que aqui mostramos 0.00 para campos que vinieron vacios
// en el XML. No es ideal, pero es la limitacion del motor. Si en el
// futuro se necesita distinguir "no vino" de "vino como 0", hay que
// cambiar la estructura: usar un caracter "?" para marcar nulos, o
// almacenar "-1" para nulos (requiere cambios en ZCI, ZCC, ZCP).
// =====================================================================
Static Function VisNum(nVal)
Return AllTrim(Transform(nVal, "@E 999,999,999.99"))

// ---------------------------------------------------------------------
Static Function VisTipo(cTipo)
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
Static Function VisTrib(cImp)
	Local cRet := AllTrim(cImp)

	Do Case
	Case cRet == "001" ; cRet := "ISR (001)"
	Case cRet == "002" ; cRet := "IVA (002)"
	Case cRet == "003" ; cRet := "IEPS (003)"
	EndCase

Return cRet

// ---------------------------------------------------------------------
// El estatus '?' NO quiere decir vigente: quiere decir que no se le ha
// preguntado al SAT. Se escribe completo para que nadie lo lea mal.
// ---------------------------------------------------------------------
Static Function VisEst(cEst)
	Local cRet := ""

	Do Case
	Case AllTrim(cEst) == "C" ; cRet := "CANCELADO"
	Case AllTrim(cEst) == "V" ; cRet := "vigente segun el SAT"
	Case AllTrim(cEst) == "N" ; cRet := "EL SAT NO CONOCE ESTE FOLIO"
	Otherwise                 ; cRet := "sin consultar al SAT"
	EndCase

Return cRet

// ---------------------------------------------------------------------
// Version corta, para que quepa en la columna del browse. El texto
// completo sigue saliendo en el Detalle.
// ---------------------------------------------------------------------
Static Function VisEstC(cEst)
	Local cRet := ""

	Do Case
	Case AllTrim(cEst) == "C" ; cRet := "CANCELADO"
	Case AllTrim(cEst) == "V" ; cRet := "vigente (SAT)"
	Otherwise                 ; cRet := "sin consultar"
	EndCase

Return cRet

// ---------------------------------------------------------------------
// Ventana de solo lectura con texto desplazable.
// ---------------------------------------------------------------------
// OJO con los nombres de variable: cVer choca con algo del framework y
// el linter lo marca como "assign to constant". Ya habia pasado en
// ZCFDI.PRW con el mismo nombre.
Static Function VisMues(cTitulo, cTexto)
	Local oDlg  := NIL
	Local oMem  := NIL
	Local cMemo := cTexto

	DEFINE MSDIALOG oDlg TITLE cTitulo FROM 0, 0 TO 500, 700 PIXEL

	@ 5, 5 GET oMem VAR cMemo MEMO SIZE 340, 225 OF oDlg PIXEL
	oMem:bWhen := {|| .F. }

	DEFINE SBUTTON FROM 232, 300 TYPE 1 ACTION oDlg:End() ENABLE OF oDlg

	ACTIVATE MSDIALOG oDlg CENTERED

Return

// ---------------------------------------------------------------------
Static Function VisAbre()
	Local aArq := {"ZCF", "ZCC", "ZCI", "ZCP"}
	Local nI   := 0

	For nI := 1 To Len(aArq)
		If Select(aArq[nI]) == 0
			If !ChkFile(aArq[nI])
				MsgStop("No se pudo abrir " + aArq[nI] + "." + CRLF + CRLF + ;
					"Si las tablas se acaban de crear, sal del modulo y" + CRLF + ;
					"vuelve a entrar: Protheus lee el diccionario al" + CRLF + ;
					"abrir la sesion.", "ZCFDIVIS")
				Return .F.
			EndIf
		EndIf
	Next nI

Return .T.
