#INCLUDE "PROTHEUS.CH"
#INCLUDE "TOPCONN.CH"

/*/{Protheus.doc} ZCFDI
Visor de CFDI - punto de entrada unico.

SOLO LECTURA en esta version. No graba, no altera, no borra.

POR QUE UNA SOLA RUTINA

Todo el visor cuelga de aqui. Se da de alta UNA entrada de menu en
Protheus y nunca mas: las opciones nuevas se agregan dentro de este
menu, no en SIGACFG. En el proyecto anterior cada rutina quedo con su
propio boton suelto y nadie se acordaba de cual era cual.

OPCION 1 - INVENTARIO DE XML

Es el primer paso del proyecto y a proposito no construye nada.

El visor se alimenta de los XML de CFDI. Antes de disenar el
diccionario hay que saber que XML existen de verdad, donde estan, de
que fechas, cuantos son, y como vienen armados por dentro. Un
diccionario disenado sobre la especificacion y no sobre los archivos
reales se rompe en la primera carga.

  A. Los parametros MV_CFD*, como referencia
  B. El arbol de carpetas del servidor, con el conteo de XML de cada una
  C. Solo las carpetas que si tienen XML, de mayor a menor
  D. El contenido de un XML de muestra, tal cual viene

LOS PARAMETROS NO SIRVEN PARA LOCALIZAR  (aprendido en el proyecto)

La primera version leia las rutas de los parametros MV_CFD* y buscaba
ahi. Devolvio cero XML, y no porque no hubiera: los parametros NO
guardan rutas, guardan EXPRESIONES de ADVPL. El valor literal de
MV_CFDDOCS es:

    GetSrvProfString('startpath','')+'\cfd\facturas\'

o sea, texto que Protheus evalua en tiempo de ejecucion. Buscar una
carpeta con ese nombre no encuentra nada.

Por eso ahora la localizacion NO depende de los parametros: se recorre
el arbol de carpetas y se reporta donde hay XML de verdad. Los
parametros se siguen listando en la seccion A, pero solo como
referencia de configuracion.

DONDE RESULTARON ESTAR (ejemplo de ambiente)

    <startpath>\CFD\FACTURAS\    los CFDI emitidos
    <startpath>\CFD\ANULADAS\    los cancelados
    <startpath>\CFD\RECPAGOS\    los complementos de pago

@author Claude + Miguel Yasec
@since 09/2026
/*/
// ---------------------------------------------------------------------
// EL MENU VA EN DOS NIVELES  (aprendido en el proyecto)
//
// Aviso() admite un maximo de TRES botones. Con cuatro truena con
// "array out of bounds ( 4 of 3 )" y el error apunta a AVISO.PRX, no al
// codigo propio, asi que cuesta leerlo.
//
// Se agrupa por lo que hace cada opcion: primero lo que solo consulta,
// aparte lo que modifica. Es mejor que una lista plana de todos modos:
// quien entre ve de entrada cuales opciones pueden cambiar algo.
// ---------------------------------------------------------------------
User Function ZCFDI()
	Local nOpc := 0

	While .T.
		nOpc := Aviso("ZCFDI - Visor de CFDI", ;
			"Ver CFDI    : la pantalla del visor" + CRLF + ;
			"Conciliar   : que PPD se cobro y no se timbro su complemento" + CRLF + ;
			"Herramientas: diagnostico y carga de datos" + CRLF + CRLF + ;
			"Para salir, cierra la ventana.", ;
			{"Ver CFDI", "Conciliar", "Herramientas"}, 3)

		Do Case
		Case nOpc == 1
			U_ZCFDIVIS()
		Case nOpc == 2
			U_ZCFDICON()
		Case nOpc == 3
			CfdHerr()
		Otherwise
			Exit
		EndCase
	EndDo

Return

// ---------------------------------------------------------------------
// Submenu de herramientas. El visor es lo que se usa a diario; esto es
// lo que se toca cuando hay que cargar datos o entender algo.
// ---------------------------------------------------------------------
Static Function CfdHerr()
	Local nOpc := 0

	While .T.
		nOpc := Aviso("ZCFDI - Herramientas", ;
			"Diagnostico: revisar los XML del servidor, sin tocar nada" + CRLF + ;
			"Construir  : crear las tablas e importar los XML" + CRLF + ;
			"             (aqui SI se escribe, y confirma antes)", ;
			{"Diagnostico", "Construir", "Volver"}, 3)

		Do Case
		Case nOpc == 1
			CfdDiag()
		Case nOpc == 2
			CfdCons()
		Otherwise
			Exit
		EndCase
	EndDo

Return

// ---------------------------------------------------------------------
// Submenu de diagnostico. Todo lo de aqui es de solo lectura.
// ---------------------------------------------------------------------
Static Function CfdDiag()
	Local nOpc := 0

	While .T.
		nOpc := Aviso("ZCFDI - Diagnostico", ;
			"Todo lo de aqui es de SOLO LECTURA." + CRLF + CRLF + ;
			"Inventario  : donde estan los XML en el servidor" + CRLF + ;
			"Caracterizar: que traen por dentro, uno por uno" + CRLF + ;
			"Probar SAT  : alcanza este servidor al SAT?" + CRLF + CRLF + ;
			"Para volver, cierra la ventana.", ;
			{"Inventario", "Caracterizar XML", "Probar SAT"}, 3)

		Do Case
		Case nOpc == 1
			Processa({|| CfdInv() }, "Recorriendo el servidor...")
		Case nOpc == 2
			Processa({|| CfdCara() }, "Leyendo los XML...")
		Case nOpc == 3
			U_ZCFDISAT()
		Otherwise
			Exit
		EndCase
	EndDo

Return

// ---------------------------------------------------------------------
// Submenu de construccion. Todo lo de aqui escribe.
//
// El orden importa: sin tablas no hay donde importar. Van en el orden
// en que se deben correr.
// ---------------------------------------------------------------------
Static Function CfdCons()
	Local nOpc := 0

	While .T.
		nOpc := Aviso("ZCFDI - Construir", ;
			"Estas opciones SI escriben." + CRLF + CRLF + ;
			"1. Crear tablas: da de alta ZCF, ZCC, ZCI, ZCP y ZCR" + CRLF + ;
			"2. Importar XML: carga los comprobantes a esas tablas" + CRLF + ;
			"3. Catalogos  : las descripciones del SAT (forma de pago," + CRLF + ;
			"                regimen, uso del CFDI, clave de producto)" + CRLF + CRLF + ;
			"La 1 y la 2 van en ese orden. La 3 se puede correr" + CRLF + ;
			"cuando sea. Las tres confirman antes de hacer nada" + CRLF + ;
			"y se pueden repetir sin duplicar." + CRLF + CRLF + ;
			"Para volver, cierra la ventana.", ;
			{"1. Crear tablas", "2. Importar XML", "3. Catalogos"}, 3)

		Do Case
		Case nOpc == 1
			U_ZCFDIDIC()
		Case nOpc == 2
			U_ZCFDIIMP()
		Case nOpc == 3
			// Vive en ZCFDICAT.PRW, que es un fuente aparte. Si no esta
			// compilado se avisa en vez de tronar: el resto del visor no
			// depende de el.
			If FindFunction("U_ZCFDICAT")
				U_ZCFDICAT()
			Else
				MsgStop("Falta compilar ZCFDICAT.PRW." + CRLF + CRLF + ;
					"Es el fuente de los catalogos del SAT. Sin el, el" + CRLF + ;
					"visor funciona igual pero muestra las claves sin" + CRLF + ;
					"su descripcion.", "ZCFDI")
			EndIf
		Otherwise
			Exit
		EndCase
	EndDo

Return

// ---------------------------------------------------------------------
Static Function CfdInv()
	Local cRep := ""
	Local cArq := ""
	Local aCon := {}   // carpetas que SI tienen XML: {ruta, cuantos}

	cRep := "=====================================================" + CRLF
	cRep += " INVENTARIO DE XML DE CFDI" + CRLF
	cRep += " Fecha: " + DToC(Date()) + "   Hora: " + Time() + CRLF
	cRep += " Empresa/Filial: " + cEmpAnt + "/" + cFilAnt + CRLF
	cRep += "=====================================================" + CRLF + CRLF
	cRep += "SOLO LECTURA. Esta corrida no modifico nada." + CRLF + CRLF

	cRep += "--- A. PARAMETROS MV_CFD* (solo de referencia) ---" + CRLF
	cRep += CfdParam()
	cRep += CRLF

	cRep += "--- B. ARBOL DE CARPETAS DEL SERVIDOR ---" + CRLF
	cRep += CfdCarp("\", 1, @aCon)
	cRep += CRLF

	cRep += "--- C. CARPETAS CON XML, DE MAYOR A MENOR ---" + CRLF
	cRep += CfdXml(aCon)
	cRep += CRLF

	cRep += "--- D. UN XML DE MUESTRA, TAL CUAL VIENE ---" + CRLF
	cRep += CfdMues(aCon)

	cArq := CfdEscr(cRep)

	MsgInfo("Inventario terminado." + CRLF + CRLF + ;
		"El detalle quedo en el archivo que se acaba de bajar" + CRLF + ;
		"a tu PC:" + CRLF + CRLF + cArq, "ZCFDI")

Return

// ---------------------------------------------------------------------
// A. Parametros MV_CFD*, como referencia de configuracion.
//
// No se usan para localizar nada: su contenido son expresiones de
// ADVPL, no rutas. Sirven para saber que esta configurado -- que PAC,
// que certificado, si CFDI 4.0 esta activo.
//
// OJO: la descripcion en SX6 es X6_DESCRIC. No existe X6_DESCSPA.
// ---------------------------------------------------------------------
Static Function CfdParam()
	Local cRet := ""
	Local cSql := ""
	Local cVal := ""
	Local nN   := 0

	cSql := "SELECT TRIM(X6_VAR) AS VARNOM, TRIM(X6_DESCRIC) AS DESCR, "
	cSql += "TRIM(X6_CONTEUD) AS VALOR "
	cSql += "FROM " + CfdTab("SX6") + " "
	cSql += "WHERE D_E_L_E_T_ = ' ' "
	cSql += "AND TRIM(X6_VAR) LIKE 'MV_CFD%' "
	cSql += "ORDER BY X6_VAR"

	TCQuery cSql New Alias "QP"

	QP->(DbGoTop())
	While !QP->(Eof())
		nN++
		cVal := AllTrim(QP->VALOR)
		cRet += "  " + PadR(AllTrim(QP->VARNOM), 13) + ;
			PadR(AllTrim(QP->DESCR), 34) + ;
			IIf(Empty(cVal), "(vacio)", cVal) + CRLF
		QP->(DbSkip())
	EndDo
	QP->(DbCloseArea())

	If nN == 0
		cRet += "  (ningun parametro MV_CFD*)" + CRLF
	EndIf

Return cRet

// ---------------------------------------------------------------------
// B. Arbol de carpetas, hasta cuatro niveles, contando los XML de cada
//    una. Las que tienen XML se van guardando en aCon.
//
// Este recorrido es el que de verdad localiza los archivos, porque no
// depende de que ningun parametro este bien configurado.
// ---------------------------------------------------------------------
Static Function CfdCarp(cRuta, nNiv, aCon)
	Local cRet := ""
	Local aDir := {}
	Local nI   := 0
	Local cSub := ""
	Local nXml := 0

	If nNiv > 4
		Return ""
	EndIf

	aDir := Directory(cRuta + "*.*", "D")

	For nI := 1 To Len(aDir)
		// aDir[nI][5] trae los atributos; "D" marca directorio
		If "D" $ aDir[nI][5] .And. aDir[nI][1] != "." .And. aDir[nI][1] != ".."
			cSub := cRuta + AllTrim(aDir[nI][1]) + "\"
			nXml := Len(Directory(cSub + "*.xml"))

			cRet += Space(nNiv * 2) + "  " + PadR(cSub, 46) + ;
				IIf(nXml > 0, cValToChar(nXml) + " XML", "") + CRLF

			If nXml > 0
				aAdd(aCon, {cSub, nXml})
			EndIf

			cRet += CfdCarp(cSub, nNiv + 1, @aCon)
		EndIf
	Next nI

	If nNiv == 1 .And. Empty(cRet)
		cRet := "  (no se pudo listar el rootpath)" + CRLF
	EndIf

Return cRet

// ---------------------------------------------------------------------
// C. Solo las carpetas que tienen XML, ordenadas por cantidad, con el
//    rango de fechas de cada una.
//
// El rango de fechas importa tanto como el conteo: si solo hay archivos
// recientes, algo los esta depurando y el visor no va a poder confiar en
// que la carpeta tenga el historico completo.
// ---------------------------------------------------------------------
Static Function CfdXml(aCon)
	Local cRet := ""
	Local nI   := 0
	Local nJ   := 0
	Local aArq := {}
	Local dMin := CToD("")
	Local dMax := CToD("")
	Local nTot := 0

	If Len(aCon) == 0
		cRet += "  No se encontro un solo XML en todo el arbol." + CRLF + CRLF
		cRet += "  Antes de construir el visor hay que resolver de donde van" + CRLF
		cRet += "  a salir: puede que Protheus los depure despues de timbrar," + CRLF
		cRet += "  que vivan en otra maquina, o que haya que bajarlos del SAT." + CRLF
		Return cRet
	EndIf

	aSort(aCon, , , {|x, y| x[2] > y[2] })

	For nI := 1 To Len(aCon)
		nTot += aCon[nI][2]
		aArq := Directory(aCon[nI][1] + "*.xml")

		dMin := CToD("")
		dMax := CToD("")
		For nJ := 1 To Len(aArq)
			// aArq[nJ][3] es la fecha del archivo
			If Empty(dMin) .Or. aArq[nJ][3] < dMin
				dMin := aArq[nJ][3]
			EndIf
			If Empty(dMax) .Or. aArq[nJ][3] > dMax
				dMax := aArq[nJ][3]
			EndIf
		Next nJ

		cRet += "  " + PadR(aCon[nI][1], 40) + ;
			PadL(cValToChar(aCon[nI][2]), 6) + " XML   " + ;
			IIf(Empty(dMin), "", "del " + DToC(dMin) + " al " + DToC(dMax)) + CRLF
	Next nI

	cRet += CRLF + "  Total: " + cValToChar(nTot) + " XML en " + ;
		cValToChar(Len(aCon)) + " carpetas" + CRLF

Return cRet

// ---------------------------------------------------------------------
// D. Un XML completo, tal cual. Es lo que va a dictar el diseno del
//    diccionario: version del CFDI, que nodos trae, si los impuestos
//    vienen a nivel concepto o a nivel comprobante, que complementos.
//
// Se prefiere la carpeta de facturas; si no, cualquiera que hable de
// CFD; y en ultimo caso la que mas archivos tenga.
// ---------------------------------------------------------------------
Static Function CfdMues(aCon)
	Local cRet := ""
	Local nI   := 0
	Local nPos := 0
	Local aArq := {}
	Local cArq := ""
	Local cTxt := ""

	If Len(aCon) == 0
		Return "  (no hay ningun XML que mostrar)" + CRLF
	EndIf

	// 1a opcion: la carpeta de facturas
	For nI := 1 To Len(aCon)
		If "FACTURA" $ Upper(aCon[nI][1])
			nPos := nI
			Exit
		EndIf
	Next nI

	// 2a opcion: cualquiera que mencione CFD
	If nPos == 0
		For nI := 1 To Len(aCon)
			If "CFD" $ Upper(aCon[nI][1])
				nPos := nI
				Exit
			EndIf
		Next nI
	EndIf

	// 3a opcion: la que mas tenga (aCon ya viene ordenado)
	If nPos == 0
		nPos := 1
	EndIf

	aArq := Directory(aCon[nPos][1] + "*.xml")

	If Len(aArq) == 0
		Return "  (la carpeta se vacio entre una lectura y otra)" + CRLF
	EndIf

	cArq := aCon[nPos][1] + AllTrim(aArq[1][1])
	cRet += "  Archivo: " + cArq + CRLF + CRLF

	cTxt := MemoRead(cArq)

	If Empty(cTxt)
		Return cRet + "  (el archivo existe pero no se pudo leer)" + CRLF
	EndIf

	If Len(cTxt) > 6000
		cRet += SubStr(cTxt, 1, 6000) + CRLF + CRLF
		cRet += "  [...recortado, el archivo mide " + ;
			cValToChar(Len(cTxt)) + " caracteres...]" + CRLF
	Else
		cRet += cTxt + CRLF
	EndIf

Return cRet

// ---------------------------------------------------------------------
// OPCION 2 - CARACTERIZAR LOS XML
//
// El inventario dice donde estan. Esto dice que son.
//
// Lee cada XML de las carpetas de CFD y extrae sus datos de cabecera:
// version, tipo de comprobante, serie, folio, fecha, metodo de pago, y
// -- lo mas importante -- si trae o no el timbre fiscal del SAT.
//
// POR QUE IMPORTA EL TIMBRE
//
// El primer XML que revisamos no traia nodo TimbreFiscalDigital: era el
// comprobante ANTES de mandarlo al PAC, sin UUID ni sello del SAT. Si
// todos son asi, estos archivos no son el acervo fiscal sino un
// subproducto del proceso de emision, y el visor NO puede alimentarse
// solo de ellos: el UUID tendria que salir de la base (F2_UUID en SF2,
// EL_UUID en SEL).
//
// Esa es la pregunta que decide la arquitectura del visor, y es la
// razon de ser de esta opcion. Una muestra de un archivo no alcanza
// para contestarla.
//
// No se usa XmlParser a proposito: para leer atributos de la cabecera
// basta con buscar texto, y asi la rutina no truena con un XML mal
// formado -- justo los que mas interesa detectar.
// ---------------------------------------------------------------------
Static Function CfdCara()
	Local cRep  := ""
	Local cArq  := ""
	Local aCon  := {}
	Local aDet  := {}
	Local nI    := 0
	Local nJ    := 0
	Local aArq  := {}
	Local cTxt  := ""
	Local cRuta := ""
	Local nTim  := 0
	Local nSin  := 0
	Local aTipo := {}
	Local aVer  := {}
	Local cTipDoc := ""
	Local cVerDoc  := ""
	Local nTot  := 0

	// localizar las carpetas de CFD reusando el recorrido del inventario
	CfdCarp("\", 1, @aCon)

	For nI := 1 To Len(aCon)
		If !("CFD" $ Upper(aCon[nI][1]))
			Loop
		EndIf

		cRuta := aCon[nI][1]
		aArq  := Directory(cRuta + "*.xml")

		ProcRegua(Len(aArq))

		For nJ := 1 To Len(aArq)
			IncProc()

			cTxt := MemoRead(cRuta + AllTrim(aArq[nJ][1]))
			If Empty(cTxt)
				Loop
			EndIf

			nTot++
			cVerDoc  := CfdAtr(cTxt, "Version")
			cTipDoc := CfdAtr(cTxt, "TipoDeComprobante")

			If "TIMBREFISCALDIGITAL" $ Upper(cTxt)
				nTim++
			Else
				nSin++
			EndIf

			CfdCta(@aVer, cVerDoc)
			CfdCta(@aTipo, cTipDoc)

			If Len(aDet) < 25
				aAdd(aDet, {AllTrim(aArq[nJ][1]), cVerDoc, cTipDoc, ;
					CfdAtr(cTxt, "MetodoPago"), ;
					SubStr(CfdAtr(cTxt, "Fecha"), 1, 10), ;
					IIf("TIMBREFISCALDIGITAL" $ Upper(cTxt), "SI", "NO"), ;
					CfdAtr(cTxt, "UUID")})
			EndIf
		Next nJ
	Next nI

	cRep := "=====================================================" + CRLF
	cRep += " CARACTERIZACION DE LOS XML DE CFD" + CRLF
	cRep += " Fecha: " + DToC(Date()) + "   Hora: " + Time() + CRLF
	cRep += "=====================================================" + CRLF + CRLF
	cRep += "SOLO LECTURA. Esta corrida no modifico nada." + CRLF + CRLF

	cRep += "--- 1. LO QUE DECIDE LA ARQUITECTURA ---" + CRLF
	cRep += "  XML leidos                  : " + cValToChar(nTot) + CRLF
	cRep += "  CON timbre fiscal del SAT   : " + cValToChar(nTim) + CRLF
	cRep += "  SIN timbre fiscal del SAT   : " + cValToChar(nSin) + CRLF + CRLF

	Do Case
	Case nTot == 0
		cRep += "  No se pudo leer ningun XML." + CRLF
	Case nSin == 0
		cRep += "  Todos traen timbre: los archivos SI son el acervo fiscal." + CRLF
		cRep += "  El visor puede alimentarse de ellos y sacar el UUID de ahi." + CRLF
	Case nTim == 0
		cRep += "  NINGUNO trae timbre. Estos archivos son el comprobante" + CRLF
		cRep += "  antes de mandarlo al PAC, no el timbrado que regresa." + CRLF
		cRep += "  El visor tendra que cruzar contra SF2/SEL para el UUID," + CRLF
		cRep += "  o habra que conseguir los timbrados del PAC o del SAT." + CRLF
	Otherwise
		cRep += "  Estan mezclados. Hay que entender que distingue a unos" + CRLF
		cRep += "  de otros antes de disenar la ingesta." + CRLF
	EndCase

	cRep += CRLF + "--- 2. POR VERSION DE CFDI ---" + CRLF
	cRep += CfdMues2(aVer)

	cRep += CRLF + "--- 3. POR TIPO DE COMPROBANTE ---" + CRLF
	cRep += CfdMues2(aTipo)
	cRep += "  (I ingreso, E egreso, T traslado, N nomina, P pago)" + CRLF

	cRep += CRLF + "--- 4. LOS PRIMEROS 25, AL DETALLE ---" + CRLF
	cRep += "  ARCHIVO                        VER  TIPO  METODO FECHA       TIMBRE" + CRLF
	For nI := 1 To Len(aDet)
		cRep += "  " + PadR(aDet[nI][1], 31) + ;
			PadR(aDet[nI][2], 5) + ;
			PadR(aDet[nI][3], 6) + ;
			PadR(aDet[nI][4], 7) + ;
			PadR(aDet[nI][5], 12) + ;
			aDet[nI][6] + CRLF
		If !Empty(aDet[nI][7])
			cRep += "     UUID: " + aDet[nI][7] + CRLF
		EndIf
	Next nI

	cArq := CfdEscr2(cRep)

	MsgInfo("Caracterizacion terminada." + CRLF + CRLF + ;
		"XML leidos: " + cValToChar(nTot) + CRLF + ;
		"Con timbre: " + cValToChar(nTim) + "    Sin timbre: " + ;
		cValToChar(nSin) + CRLF + CRLF + ;
		"Detalle en:" + CRLF + cArq, "ZCFDI")

Return

// ---------------------------------------------------------------------
// Valor de un atributo XML por nombre. Devuelve "" si no aparece.
// ---------------------------------------------------------------------
Static Function CfdAtr(cTxt, cAtr)
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

Return cRet

// ---------------------------------------------------------------------
// Acumula un conteo por valor en un arreglo {valor, cuantos}
// ---------------------------------------------------------------------
Static Function CfdCta(aAcu, cVal)
	Local nPos := 0
	Local cUso := ""

	// no se asigna al parametro: el linter de TOTVS lo marca como
	// "assign to constant" cuando lo recibe por valor
	cUso := IIf(Empty(cVal), "(sin dato)", cVal)

	nPos := aScan(aAcu, {|x| x[1] == cUso })
	If nPos == 0
		aAdd(aAcu, {cUso, 0})
		nPos := Len(aAcu)
	EndIf
	aAcu[nPos][2]++

Return

// ---------------------------------------------------------------------
Static Function CfdMues2(aAcu)
	Local cRet := ""
	Local nI   := 0

	If Len(aAcu) == 0
		Return "  (nada que contar)" + CRLF
	EndIf

	aSort(aAcu, , , {|x, y| x[2] > y[2] })

	For nI := 1 To Len(aAcu)
		cRet += "  " + PadR(aAcu[nI][1], 14) + ;
			PadL(cValToChar(aAcu[nI][2]), 6) + CRLF
	Next nI

Return cRet

// ---------------------------------------------------------------------
Static Function CfdEscr2(cRep)
	Local cDir  := "\zcfdi\"
	Local cNom  := "caracteriza_cfdi_" + DToS(Date()) + ".txt"
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

// ---------------------------------------------------------------------
// Nombre fisico de una tabla en el ambiente donde se este corriendo.
// El sufijo es el del grupo de empresas y cambia entre ambientes, asi
// que no se escribe a mano.
// ---------------------------------------------------------------------
Static Function CfdTab(cAlias)
	Local cAli := AllTrim(cAlias)
	Local cRet := AllTrim(RetSqlName(cAli))
	Local cSuf := ""

	If Empty(cRet) .Or. cRet == cAli
		cSuf := SubStr(AllTrim(RetSqlName("SF2")), 4)
		cRet := cAli + cSuf
	EndIf

Return cRet

// ---------------------------------------------------------------------
Static Function CfdEscr(cRep)
	// carpeta propia del proyecto en el servidor; el destino en la PC se
	// deja en la que ya existe, para no depender de crearla
	Local cDir  := "\zcfdi\"
	Local cNom  := "inventario_cfdi_" + DToS(Date()) + ".txt"
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
