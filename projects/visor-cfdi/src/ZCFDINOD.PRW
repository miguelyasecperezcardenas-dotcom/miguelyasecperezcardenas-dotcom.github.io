#INCLUDE "PROTHEUS.CH"
#INCLUDE "TOPCONN.CH"

/*/{Protheus.doc} ZCFDINOD
Censo de nodos: que trae REALMENTE el XML de los CFDI de la empresa.

POR QUE ESTO ANTES DE PROGRAMAR

El visor hoy captura cabecera, conceptos, impuestos y complemento de
pagos. La pregunta "que nodos faltan" se puede contestar de dos formas:
leyendo la especificacion del CFDI 4.0, o leyendo los archivos.

La especificacion admite decenas de complementos -- comercio exterior,
carta porte, nomina, donatarias, leyendas fiscales, instituciones
educativas, impuestos locales... Programarlos todos seria trabajo para
semanas, y casi todos no aparecerian nunca en un XML real del cliente.

Esta rutina cuenta lo que hay. Despues se programa lo que salio.

COMO CUENTA

No usa XmlParser. Recorre el TEXTO del archivo buscando etiquetas.

Suena rudimentario y es a proposito: XmlParser devuelve un objeto cuyos
hijos hay que conocer de antemano para poder recorrerlos, y aqui la
pregunta es justamente cuales son. Ademas XmlParser devuelve un objeto
cuando un nodo aparece una vez y un arreglo cuando aparece varias, lo
que ya costo tiempo en este proyecto. Leer el texto no tiene esa
ambiguedad: una etiqueta es una etiqueta.

Se arma la RUTA COMPLETA de cada nodo, no solo su nombre:

  cfdi:Comprobante/cfdi:Conceptos/cfdi:Concepto/cfdi:Impuestos

Asi se distingue un nodo Impuestos a nivel comprobante de uno a nivel
concepto, que es una distincion que importa y que un conteo por nombre
perderia.

Los atributos se cuentan como la ruta mas "@nombre".

QUE SE CUENTA

En cuantos ARCHIVOS aparece cada ruta, no cuantas veces en total. Que un
nodo aparezca 400 veces porque hay 400 conceptos no dice nada; que
aparezca en pocos archivos si.

SOLO LEE. No toca ninguna tabla.

@author Claude + Miguel Yasec
@since 10/2026
/*/
User Function ZCFDINOD()
	Local aCar := {}
	Local aNod := {}
	Local nTope := 0
	Local nArch := 0
	Local cTxt  := ""
	Local cArq  := ""

	nTope := NodTope()

	If nTope < 0
		Return
	EndIf

	NodCarp(@aCar)

	If Len(aCar) == 0
		MsgStop("No se encontro ninguna carpeta con XML.", "ZCFDINOD")
		Return
	EndIf

	nArch := NodCenso(aCar, nTope, @aNod)

	If nArch == 0
		MsgStop("No se leyo ningun XML.", "ZCFDINOD")
		Return
	EndIf

	NodOrd(@aNod)

	cTxt := NodTexto(aNod, nArch, Len(aCar))
	cArq := NodEscr(cTxt, "censo_nodos_")

	NodMues("Censo de nodos", cTxt + CRLF + CRLF + ;
		"Copia completa en:" + CRLF + "  " + cArq + CRLF)

Return

// ---------------------------------------------------------------------
// Cuantos archivos. Leer muchos archivos caracter por caracter no es
// gratis, asi que se pregunta antes en vez de dejar al usuario mirando
// una pantalla congelada.
// ---------------------------------------------------------------------
Static Function NodTope()
	Local nOpc := 0

	nOpc := Aviso("Censo de nodos", ;
		"Se van a leer los XML del servidor para contar que nodos traen." + CRLF + CRLF + ;
		"No se toca ninguna tabla: esto solo lee." + CRLF + CRLF + ;
		"Con 50 archivos ya se ve el panorama. Todos tarda mas pero" + CRLF + ;
		"es el que encuentra los complementos raros, que son justo" + CRLF + ;
		"los que interesan.", ;
		{"50", "200", "Todos"})

	Do Case
	Case nOpc == 1 ; Return 50
	Case nOpc == 2 ; Return 200
	Case nOpc == 3 ; Return 0     // sin tope
	EndCase

Return -1

// ---------------------------------------------------------------------
// El censo. Devuelve cuantos archivos se leyeron.
// ---------------------------------------------------------------------
Static Function NodCenso(aCar, nTope, aNod)
	Local aArq := {}
	Local nI   := 0
	Local nJ   := 0
	Local nN   := 0
	Local cNom := ""
	Local cTxt := ""
	Local aEste := {}

	For nI := 1 To Len(aCar)

		aArq := Directory(aCar[nI] + "*.xml")

		For nJ := 1 To Len(aArq)

			cNom := AllTrim(aArq[nJ][1])

			// Los _ORIGIN son la copia anterior al timbrado. Contarlos
			// inflaria el censo con nodos que el comprobante bueno
			// tambien trae, y ensuciaria el conteo de "cuantos
			// archivos" con duplicados del mismo comprobante.
			If "_ORIGIN" $ Upper(cNom)
				Loop
			EndIf

			cTxt := MemoRead(aCar[nI] + cNom)

			If Empty(cTxt)
				Loop
			EndIf

			nN++

			// Las rutas de ESTE archivo, sin repetir: se cuenta en
			// cuantos archivos aparece cada una, no cuantas veces.
			aEste := {}
			NodLee(cTxt, @aEste)
			NodSuma(aEste, @aNod)

			If nTope > 0 .And. nN >= nTope
				Return nN
			EndIf

		Next nJ
	Next nI

Return nN

// ---------------------------------------------------------------------
// Saca las rutas de un XML. Una pasada por el texto.
// ---------------------------------------------------------------------
Static Function NodLee(cTxt, aEste)
	Local aPart := {}
	Local aPila := {}
	Local nI    := 0
	Local cPart := ""
	Local cTag  := ""
	Local cRuta := ""
	Local nFin  := 0
	Local lCierra := .F.
	Local lSolo   := .F.

	// Partir por "<" deja cada etiqueta al inicio de su pedazo. Es la
	// forma mas simple de recorrer sin ir caracter por caracter.
	aPart := StrTokArr(cTxt, "<")

	For nI := 1 To Len(aPart)

		cPart := aPart[nI]

		If Empty(cPart)
			Loop
		EndIf

		// Declaracion, comentario o CDATA: no son nodos.
		If Left(cPart, 1) $ "?!"
			Loop
		EndIf

		lCierra := (Left(cPart, 1) == "/")

		If lCierra
			If Len(aPila) > 0
				aSize(aPila, Len(aPila) - 1)
			EndIf
			Loop
		EndIf

		// El nombre va hasta el primer espacio, ">" o "/".
		nFin := NodCorta(cPart)
		cTag := Left(cPart, nFin - 1)

		If Empty(cTag)
			Loop
		EndIf

		// Se cierra sobre si misma? Entonces no abre nivel.
		lSolo := NodSolo(cPart)

		aAdd(aPila, cTag)
		cRuta := NodRuta(aPila)

		NodPon(aEste, cRuta)
		NodAtrib(cPart, cRuta, @aEste)

		If lSolo
			aSize(aPila, Len(aPila) - 1)
		EndIf

	Next nI

Return

// ---------------------------------------------------------------------
// Donde termina el nombre de la etiqueta.
// ---------------------------------------------------------------------
Static Function NodCorta(cPart)
	Local nI := 0
	Local cC := ""

	For nI := 1 To Len(cPart)
		cC := SubStr(cPart, nI, 1)
		If cC == " " .Or. cC == ">" .Or. cC == "/" .Or. ;
		   cC == Chr(9) .Or. cC == Chr(13) .Or. cC == Chr(10)
			Return nI
		EndIf
	Next nI

Return Len(cPart) + 1

// ---------------------------------------------------------------------
// La etiqueta se cierra sola (<x ... />)?
//
// Se busca la "/" que esta JUSTO antes del ">" que cierra la etiqueta,
// no cualquier "/": las rutas y las fechas de los atributos traen
// diagonales y darian un falso positivo.
// ---------------------------------------------------------------------
Static Function NodSolo(cPart)
	Local nMay := At(">", cPart)

	If nMay < 2
		Return .F.
	EndIf

Return SubStr(cPart, nMay - 1, 1) == "/"

// ---------------------------------------------------------------------
Static Function NodRuta(aPila)
	Local cRet := ""
	Local nI   := 0

	For nI := 1 To Len(aPila)
		cRet += IIf(nI > 1, "/", "") + aPila[nI]
	Next nI

Return cRet

// ---------------------------------------------------------------------
// Los atributos de la etiqueta.
//
// Se recorre el pedazo saltando de "=" en "=": el nombre es lo que esta
// antes, el valor viene entre comillas despues. Saltarse el valor
// completo es lo que evita confundir un "=" que venga adentro de una
// descripcion con el de un atributo.
// ---------------------------------------------------------------------
Static Function NodAtrib(cPart, cRuta, aEste)
	Local nMay := At(">", cPart)
	Local cSeg := ""
	Local nI   := 0
	Local nIni := 0
	Local cC   := ""
	Local cNom := ""

	cSeg := IIf(nMay > 0, Left(cPart, nMay - 1), cPart)

	// saltarse el nombre de la etiqueta
	nI := NodCorta(cSeg)

	Do While nI <= Len(cSeg)

		cC := SubStr(cSeg, nI, 1)

		// Se junta el nombre del atributo hasta el "="
		If cC == " " .Or. cC == Chr(9) .Or. cC == Chr(13) .Or. cC == Chr(10)
			nI++
			Loop
		EndIf

		nIni := nI
		Do While nI <= Len(cSeg) .And. SubStr(cSeg, nI, 1) != "=" .And. ;
		         SubStr(cSeg, nI, 1) != " "
			nI++
		EndDo

		cNom := AllTrim(SubStr(cSeg, nIni, nI - nIni))

		If SubStr(cSeg, nI, 1) != "="
			nI++
			Loop
		EndIf

		nI++   // el "="

		// saltarse el valor entrecomillado completo
		If SubStr(cSeg, nI, 1) == '"'
			nI++
			Do While nI <= Len(cSeg) .And. SubStr(cSeg, nI, 1) != '"'
				nI++
			EndDo
			nI++
		EndIf

		If !Empty(cNom)
			NodPon(aEste, cRuta + "  @" + cNom)
		EndIf

	EndDo

Return

// ---------------------------------------------------------------------
// Agrega una ruta a las de este archivo, sin repetir.
// ---------------------------------------------------------------------
Static Function NodPon(aEste, cRuta)

	If aScan(aEste, {|x| x == cRuta }) == 0
		aAdd(aEste, cRuta)
	EndIf

Return

// ---------------------------------------------------------------------
// Suma las rutas de un archivo al acumulado.
// ---------------------------------------------------------------------
Static Function NodSuma(aEste, aNod)
	Local nI   := 0
	Local nPos := 0

	For nI := 1 To Len(aEste)
		nPos := aScan(aNod, {|x| x[1] == aEste[nI] })
		If nPos == 0
			aAdd(aNod, {aEste[nI], 1})
		Else
			aNod[nPos][2]++
		EndIf
	Next nI

Return

// ---------------------------------------------------------------------
// Ordena por ruta, para que el reporte se lea como un arbol.
// ---------------------------------------------------------------------
Static Function NodOrd(aNod)
	aSort(aNod, , , {|x, y| x[1] < y[1] })
Return

// ---------------------------------------------------------------------
Static Function NodTexto(aNod, nArch, nCar)
	Local cRet := ""
	Local nI   := 0
	Local nFal := 0
	Local nRui := 0
	Local nFue := 0
	Local cMar := ""

	cRet += "=== CENSO DE NODOS ===" + CRLF + CRLF
	cRet += "  Carpetas revisadas : " + Str(nCar, 5) + CRLF
	cRet += "  Archivos leidos    : " + Str(nArch, 5) + ;
		"   (sin contar los _ORIGIN)" + CRLF
	cRet += "  Rutas distintas    : " + Str(Len(aNod), 5) + CRLF + CRLF

	cRet += "  [x] el visor ya lo captura" + CRLF
	cRet += "  [ ] FALTA por programar" + CRLF
	cRet += "  [-] no es un dato (xmlns, schemaLocation)" + CRLF
	cRet += "  [~] fuera de alcance a proposito (sellos)" + CRLF + CRLF
	cRet += "  El numero es en cuantos archivos aparece." + CRLF + CRLF
	cRet += "  " + Replicate("-", 92) + CRLF

	For nI := 1 To Len(aNod)
		Do Case
		Case NodYa(aNod[nI][1])
			cMar := "[x]"
		Case NodRuido(aNod[nI][1])
			cMar := "[-]"
			nRui++
		Case NodFuera(aNod[nI][1])
			cMar := "[~]"
			nFue++
		Otherwise
			cMar := "[ ]"
			nFal++
		EndCase
		cRet += "  " + cMar + " " + Str(aNod[nI][2], 5) + "  " + aNod[nI][1] + CRLF
	Next nI

	cRet += "  " + Replicate("-", 92) + CRLF + CRLF
	cRet += "  De " + cValToChar(Len(aNod)) + " rutas:" + CRLF
	cRet += "    capturadas              : " + ;
		cValToChar(Len(aNod) - nFal - nRui - nFue) + CRLF
	cRet += "    FALTAN por programar    : " + cValToChar(nFal) + CRLF
	cRet += "    no son datos            : " + cValToChar(nRui) + CRLF
	cRet += "    fuera de alcance        : " + cValToChar(nFue) + CRLF + CRLF

	cRet += "  COMO LEER ESTO" + CRLF + CRLF
	cRet += "  Una ruta que aparece en POCOS archivos no es menos" + CRLF
	cRet += "  importante: suele ser un complemento que solo usan" + CRLF
	cRet += "  algunos proveedores, y es justo el que nadie nota que" + CRLF
	cRet += "  falta. Los impuestos locales salieron asi." + CRLF + CRLF
	cRet += "  Una que aparece en TODOS y no se captura es un hueco" + CRLF
	cRet += "  en el camino principal, y esos se arreglan primero." + CRLF

Return cRet

// ---------------------------------------------------------------------
// El visor ya captura esta ruta?
//
// La lista esta escrita a mano contra lo que ZCFDIIMP lee hoy. Es
// deliberadamente conservadora: ante la duda se marca como NO
// capturada. Un falso "ya esta" esconde trabajo pendiente; un falso
// "falta" solo cuesta una revisada.
// ---------------------------------------------------------------------
Static Function NodYa(cRuta)
	Local cR := Upper(cRuta)

	// EL ESPACIO DE NOMBRES SE COMPRUEBA PRIMERO, Y NO ES UN DETALLE.
	//
	// NodEnLis compara solo el ULTIMO tramo de la ruta, y hay nombres
	// que se repiten entre complementos: carta porte tambien tiene
	// Mercancias, Mercancia y Domicilio. Sin este filtro, agregar esos
	// nombres para comercio exterior marcaba como capturadas 9 rutas de
	// carta porte que no se leen ni de lejos -- un falso "ya esta", que
	// es el peor error posible en la herramienta cuyo unico trabajo es
	// decir que falta.
	If "CARTAPORTE31:" $ cR
		If "CARTAPORTE  @" $ cR
			Return NodEnLis(cR, "VERSION/IDCCP/TRANSPINTERNAC/TOTALDISTREC")
		EndIf
		If "MERCANCIAS  @" $ cR
			Return NodEnLis(cR, "NUMTOTALMERCANCIAS/PESOBRUTOTOTAL/UNIDADPESO")
		EndIf
		If "MERCANCIA  @" $ cR
			Return NodEnLis(cR, "BIENESTRANSP/DESCRIPCION/CANTIDAD/" + ;
				"CLAVEUNIDAD/PESOENKG/VALORMERCANCIA/MONEDA")
		EndIf
		If "AUTOTRANSPORTE  @" $ cR
			Return NodEnLis(cR, "PERMSCT/NUMPERMISOSCT")
		EndIf
		If "IDENTIFICACIONVEHICULAR  @" $ cR
			Return NodEnLis(cR, "PLACAVM/ANIOMODELOVM/CONFIGVEHICULAR")
		EndIf
		If "SEGUROS  @" $ cR
			Return NodEnLis(cR, "ASEGURARESPCIVIL/POLIZARESPCIVIL")
		EndIf
		If "UBICACION  @" $ cR
			Return NodEnLis(cR, "TIPOUBICACION/RFCREMITENTEDESTINATARIO/" + ;
				"NOMBREREMITENTEDESTINATARIO/FECHAHORASALIDALLEGADA/" + ;
				"DISTANCIARECORRIDA")
		EndIf
		If "DOMICILIO  @" $ cR
			Return NodEnLis(cR, "CALLE/NUMEROEXTERIOR/CODIGOPOSTAL/" + ;
				"LOCALIDAD/MUNICIPIO/ESTADO/PAIS")
		EndIf
		If "TIPOSFIGURA  @" $ cR
			Return NodEnLis(cR, "TIPOFIGURA/RFCFIGURA/NOMBREFIGURA/NUMLICENCIA")
		EndIf
		If !("@" $ cR)
			Return NodEnLis(cR, "CARTAPORTE/UBICACIONES/UBICACION/" + ;
				"DOMICILIO/MERCANCIAS/MERCANCIA/AUTOTRANSPORTE/" + ;
				"IDENTIFICACIONVEHICULAR/SEGUROS/FIGURATRANSPORTE/" + ;
				"TIPOSFIGURA")
		EndIf
		Return .F.
	EndIf

	If "CCE20:" $ cR
		If "COMERCIOEXTERIOR  @" $ cR
			Return NodEnLis(cR, "VERSION/CLAVEDEPEDIMENTO/" + ;
				"CERTIFICADOORIGEN/NUMEROEXPORTADORCONFIABLE/INCOTERM/" + ;
				"MOTIVOTRASLADO/TIPOCAMBIOUSD/TOTALUSD")
		EndIf
		If "RECEPTOR  @" $ cR
			Return NodEnLis(cR, "NUMREGIDTRIB")
		EndIf
		If "DOMICILIO  @" $ cR
			Return NodEnLis(cR, "CALLE/CODIGOPOSTAL/COLONIA/MUNICIPIO/" + ;
				"ESTADO/PAIS")
		EndIf
		If "MERCANCIA  @" $ cR
			Return NodEnLis(cR, "NOIDENTIFICACION/FRACCIONARANCELARIA/" + ;
				"CANTIDADADUANA/UNIDADADUANA/VALORUNITARIOADUANA/" + ;
				"VALORDOLARES")
		EndIf
		If !("@" $ cR)
			Return NodEnLis(cR, "COMERCIOEXTERIOR/EMISOR/RECEPTOR/" + ;
				"DOMICILIO/MERCANCIAS/MERCANCIA")
		EndIf
		Return .F.
	EndIf

	If "PAGO20:" $ cR
		If "PAGO  @" $ cR
			Return NodEnLis(cR, "FECHAPAGO/FORMADEPAGOP/MONEDAP/" + ;
				"TIPOCAMBIOP/MONTO/NUMOPERACION")
		EndIf
		If "DOCTORELACIONADO  @" $ cR
			Return NodEnLis(cR, "IDDOCUMENTO/SERIE/FOLIO/NUMPARCIALIDAD/" + ;
				"IMPSALDOANT/IMPPAGADO/IMPSALDOINSOLUTO/OBJETOIMPDR/" + ;
				"MONEDADR/EQUIVALENCIADR")
		EndIf
		If ("TRASLADODR  @" $ cR) .Or. ("RETENCIONDR  @" $ cR)
			Return NodEnLis(cR, "BASEDR/IMPUESTODR/TIPOFACTORDR/" + ;
				"TASAOCUOTADR/IMPORTEDR")
		EndIf
		If ("TRASLADOP  @" $ cR) .Or. ("RETENCIONP  @" $ cR)
			Return NodEnLis(cR, "BASEP/IMPUESTOP/TIPOFACTORP/" + ;
				"TASAOCUOTAP/IMPORTEP")
		EndIf
		If "TOTALES  @" $ cR
			Return NodEnLis(cR, "MONTOTOTALPAGOS/" + ;
				"TOTALTRASLADOSBASEIVA16/TOTALTRASLADOSIMPUESTOIVA16")
		EndIf
		If !("@" $ cR)
			Return NodEnLis(cR, "PAGOS/PAGO/DOCTORELACIONADO/TOTALES/" + ;
				"IMPUESTOSDR/TRASLADOSDR/TRASLADODR/RETENCIONESDR/" + ;
				"RETENCIONDR/IMPUESTOSP/TRASLADOSP/TRASLADOP/" + ;
				"RETENCIONESP/RETENCIONP")
		EndIf
		Return .F.
	EndIf

	// --- De aqui para abajo, solo cfdi: y tfd: ---

	If "COMPROBANTE  @" $ cR
		Return NodEnLis(cR, "VERSION/SERIE/FOLIO/FECHA/FORMAPAGO/" + ;
			"METODOPAGO/CONDICIONESDEPAGO/MONEDA/TIPOCAMBIO/SUBTOTAL/" + ;
			"DESCUENTO/TOTAL/TIPODECOMPROBANTE/LUGAREXPEDICION/" + ;
			"EXPORTACION/NOCERTIFICADO")
	EndIf

	If "EMISOR  @" $ cR
		Return NodEnLis(cR, "RFC/NOMBRE/REGIMENFISCAL")
	EndIf

	If "RECEPTOR  @" $ cR
		Return NodEnLis(cR, "RFC/NOMBRE/USOCFDI/DOMICILIOFISCALRECEPTOR/" + ;
			"REGIMENFISCALRECEPTOR/NUMREGIDTRIB/RESIDENCIAFISCAL")
	EndIf

	If "CONCEPTO  @" $ cR
		Return NodEnLis(cR, "CLAVEPRODSERV/NOIDENTIFICACION/CANTIDAD/" + ;
			"CLAVEUNIDAD/UNIDAD/DESCRIPCION/VALORUNITARIO/IMPORTE/" + ;
			"DESCUENTO/OBJETOIMP")
	EndIf

	If "INFORMACIONADUANERA  @" $ cR
		Return NodEnLis(cR, "NUMEROPEDIMENTO")
	EndIf

	If "CFDIRELACIONADOS  @" $ cR
		Return NodEnLis(cR, "TIPORELACION")
	EndIf

	If "CFDIRELACIONADO  @" $ cR
		Return NodEnLis(cR, "UUID")
	EndIf

	If ("TRASLADO  @" $ cR) .Or. ("RETENCION  @" $ cR)
		Return NodEnLis(cR, "BASE/IMPUESTO/TIPOFACTOR/TASAOCUOTA/IMPORTE")
	EndIf

	If "IMPUESTOS  @" $ cR
		Return NodEnLis(cR, "TOTALIMPUESTOSTRASLADADOS/TOTALIMPUESTOSRETENIDOS")
	EndIf

	If "TIMBREFISCALDIGITAL  @" $ cR
		Return NodEnLis(cR, "UUID/FECHATIMBRADO/RFCPROVCERTIF/NOCERTIFICADOSAT")
	EndIf

	// --- Nodos contenedores: no traen dato propio ---
	//
	// Aqui iba cR + "  @" y estaba mal: NodEnLis corta por el ultimo
	// "@" y se quedaba con una cadena vacia, asi que TODOS los
	// contenedores salian como no capturados. NodEnLis ya sabe quedarse
	// con el ultimo tramo de la ruta cuando no hay "@".
	If !("@" $ cR)
		Return NodEnLis(cR, ;
			"COMPROBANTE/EMISOR/RECEPTOR/CONCEPTOS/CONCEPTO/IMPUESTOS/" + ;
			"TRASLADOS/TRASLADO/RETENCIONES/RETENCION/COMPLEMENTO/" + ;
			"TIMBREFISCALDIGITAL/INFORMACIONADUANERA/" + ;
			"CFDIRELACIONADOS/CFDIRELACIONADO")
	EndIf

Return .F.

// ---------------------------------------------------------------------
// NO ES UN DATO DEL COMPROBANTE
//
// Las declaraciones de espacio de nombres y el schemaLocation son
// plomeria del XML, no informacion fiscal. Contarlas junto a lo que
// falta por programar infla el pendiente y hace que cada vez que
// alguien lee el censo tenga que volver a descartarlas a mano.
// ---------------------------------------------------------------------
Static Function NodRuido(cRuta)
	Local cR := Upper(cRuta)
Return ("@XMLNS" $ cR) .Or. ("SCHEMALOCATION" $ cR)

// ---------------------------------------------------------------------
// FUERA DE ALCANCE A PROPOSITO
//
// Los sellos y el certificado se decidieron NO capturar: son cadenas
// base64 de 500 a 700 caracteres cuyo unico uso es revalidar la firma
// por cuenta propia, y eso es un proyecto aparte, no una columna de un
// visor. Lo que si se consulta -- NoCertificado y NoCertificadoSAT --
// ya se guarda.
//
// Se marcan distinto que lo pendiente para que la decision quede a la
// vista y no haya que volver a discutirla en cada revision.
// ---------------------------------------------------------------------
Static Function NodFuera(cRuta)
	Local cR := Upper(cRuta)
Return ("@SELLO" $ cR) .Or. ("@CERTIFICADO" $ cR)

// ---------------------------------------------------------------------
// El ultimo pedazo de la ruta (nodo o atributo) esta en la lista?
// ---------------------------------------------------------------------
Static Function NodEnLis(cRuta, cLista)
	Local cUlt := cRuta
	Local nPos := 0

	nPos := RAt("@", cUlt)
	If nPos > 0
		cUlt := SubStr(cUlt, nPos + 1)
	Else
		nPos := RAt("/", cUlt)
		If nPos > 0
			cUlt := SubStr(cUlt, nPos + 1)
		EndIf
		// quitar el prefijo de espacio de nombres (cfdi:, tfd:, pago20:)
		nPos := At(":", cUlt)
		If nPos > 0
			cUlt := SubStr(cUlt, nPos + 1)
		EndIf
	EndIf

	cUlt := AllTrim(cUlt)

Return ("/" + cUlt + "/") $ ("/" + cLista + "/")

// ---------------------------------------------------------------------
Static Function NodCarp(aCar)
	NodAnda("\", 1, @aCar)
Return

// ---------------------------------------------------------------------
Static Function NodAnda(cRuta, nNiv, aCar)
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

			NodAnda(cSub, nNiv + 1, @aCar)
		EndIf
	Next nI

Return

// ---------------------------------------------------------------------
Static Function NodMues(cTitulo, cTexto)
	Local oDlg  := NIL
	Local oMem  := NIL
	Local cMemo := cTexto

	DEFINE MSDIALOG oDlg TITLE cTitulo FROM 0, 0 TO 600, 1000 PIXEL

	@ 5, 5 GET oMem VAR cMemo MEMO SIZE 490, 275 OF oDlg PIXEL
	oMem:bWhen := {|| .F. }

	DEFINE SBUTTON FROM 282, 445 TYPE 1 ACTION oDlg:End() ENABLE OF oDlg

	ACTIVATE MSDIALOG oDlg CENTERED

Return

// =====================================================================
// QUE ARCHIVOS TRAEN UN NODO
//
// El censo contesta "en cuantos archivos aparece X". La siguiente
// pregunta siempre es "en CUALES", y sin ella uno no puede saber si un
// nodo que el visor no esta guardando viene en comprobantes timbrados
// (y entonces falta codigo) o solo en borradores sin timbre (y entonces
// no falta nada). Esa duda ya costo una tarde con @NumRegIdTrib.
//
// Por eso lista el archivo CON su situacion: si trae timbre y si es
// _ORIGIN. Son los dos datos que deciden si el caso importa.
// =====================================================================
User Function ZCFDINOF()
	Local aCar := {}
	Local cBus := Space(60)
	Local cTxt := ""
	Local cArq := ""

	If !NodPide(@cBus)
		Return
	EndIf

	cBus := AllTrim(cBus)

	If Empty(cBus)
		MsgStop("No escribiste que buscar.", "ZCFDINOF")
		Return
	EndIf

	NodCarp(@aCar)

	If Len(aCar) == 0
		MsgStop("No se encontro ninguna carpeta con XML.", "ZCFDINOF")
		Return
	EndIf

	// Sin Processa: asignar un Local desde dentro de un codeblock no es
	// confiable en ADVPL y ya costo tiempo en ZCFDIPPD. Leer los XML
	// tarda unos segundos y se aguanta sin barra de avance.
	cTxt := NodBusca(aCar, cBus)
	cArq := NodEscr(cTxt, "buscar_nodo_")

	NodMues("Archivos con " + cBus, cTxt + CRLF + CRLF + ;
		"Copia completa en:" + CRLF + "  " + cArq + CRLF)

Return

// ---------------------------------------------------------------------
// DEJAR EL REPORTE EN UN ARCHIVO, NO SOLO EN LA PANTALLA
//
// La ventana del censo no cabe en una captura y no se puede copiar: el
// memo esta deshabilitado para que nadie lo edite por accidente. Un
// reporte que solo se puede mirar no sirve para comparar dos corridas
// ni para mandarselo a nadie. Se escribe en el servidor y se baja a la
// misma carpeta donde ya caen los demas diagnosticos, igual que hace
// la caracterizacion.
// ---------------------------------------------------------------------
Static Function NodEscr(cRep, cPref)
	Local cDir  := "\zcfdi\"
	Local cNom  := cPref + DToS(Date()) + "_" + ;
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

// ---------------------------------------------------------------------
// Un MSGET para el texto a buscar. MSGET si escribe de vuelta en su
// variable al cerrar la ventana (el que no lo hace es MSCOMBOBOX).
// ---------------------------------------------------------------------
Static Function NodPide(cBus)
	Local oDlg := NIL
	Local lOk  := .F.

	DEFINE MSDIALOG oDlg TITLE "Buscar un nodo o atributo" FROM 0, 0 TO 180, 500 PIXEL

	@ 10, 10 SAY "Texto a buscar dentro del XML. Sirve el nombre de un" OF oDlg PIXEL
	@ 20, 10 SAY "atributo (NumRegIdTrib) o de un nodo (cce20:Mercancia)." OF oDlg PIXEL
	@ 30, 10 SAY "No distingue mayusculas." OF oDlg PIXEL

	@ 48, 10 GET cBus SIZE 220, 10 OF oDlg PIXEL

	DEFINE SBUTTON FROM 68, 130 TYPE 1 ACTION (lOk := .T., oDlg:End()) ENABLE OF oDlg
	DEFINE SBUTTON FROM 68, 175 TYPE 2 ACTION oDlg:End() ENABLE OF oDlg

	ACTIVATE MSDIALOG oDlg CENTERED

Return lOk

// ---------------------------------------------------------------------
// Recorre TODOS los XML, incluidos los _ORIGIN: aqui si importan,
// porque la pregunta es justamente si el nodo solo vive en ellos.
// ---------------------------------------------------------------------
// ---------------------------------------------------------------------
// EL TEXTO ALREDEDOR DE LA COINCIDENCIA
//
// Saber en que archivos esta un nodo contesta "existe?", pero no
// contesta "que dice". Esa segunda pregunta aparece siempre que un
// dato sale raro y hay que decidir si el error es del parser o del
// XML -- y sin ver el texto no hay forma de decidirlo, solo de
// suponerlo. Ya paso con los CFDI relacionados, que salieron
// apuntandose a si mismos.
//
// Se muestran 60 caracteres antes y 120 despues, con los saltos de
// linea aplanados para que quepa en un renglon.
// ---------------------------------------------------------------------
Static Function NodCtx(cTxt, cUpB)
	Local nPos := At(cUpB, Upper(cTxt))
	Local nIni := 0
	Local cRet := ""

	If nPos == 0
		Return ""
	EndIf

	nIni := Max(1, nPos - 60)
	cRet := SubStr(cTxt, nIni, 180)
	cRet := StrTran(StrTran(cRet, CRLF, " "), Chr(10), " ")
	cRet := StrTran(cRet, Chr(9), " ")

Return "      ..." + AllTrim(cRet) + "..."

// ---------------------------------------------------------------------
Static Function NodBusca(aCar, cBus)
	Local aArq := {}
	Local nI   := 0
	Local nJ   := 0
	Local nTot := 0
	Local nHay := 0
	Local nTim := 0
	Local nOri := 0
	Local cNom := ""
	Local cTxt := ""
	Local cUpB := Upper(cBus)
	Local cRet := ""
	Local cLis := ""
	Local lTim := .F.
	Local lOri := .F.
	Local cEti := ""

	For nI := 1 To Len(aCar)
		aArq := Directory(aCar[nI] + "*.xml")

		For nJ := 1 To Len(aArq)
			cNom := AllTrim(aArq[nJ][1])
			cTxt := MemoRead(aCar[nI] + cNom)

			If Empty(cTxt)
				Loop
			EndIf

			nTot++

			If !(cUpB $ Upper(cTxt))
				Loop
			EndIf

			nHay++

			lTim := "TIMBREFISCALDIGITAL" $ Upper(cTxt)
			lOri := "_ORIGIN" $ Upper(cNom)

			If lTim
				nTim++
			EndIf
			If lOri
				nOri++
			EndIf

			cEti := IIf(lTim, "timbrado", "SIN TIMBRE")
			If lOri
				cEti += ", _ORIGIN"
			EndIf

			// Se cortan los nombres largos para que la columna de la
			// situacion no se recorra y la lista siga siendo legible.
			cLis += "  " + PadR(cNom, 42) + "  (" + cEti + ")" + CRLF
			cLis += NodCtx(cTxt, cUpB) + CRLF

		Next nJ
	Next nI

	cRet := "--- ARCHIVOS QUE CONTIENEN: " + cBus + " ---" + CRLF + CRLF
	cRet += "  XML revisados          : " + cValToChar(nTot) + CRLF
	cRet += "  Lo contienen           : " + cValToChar(nHay) + CRLF
	cRet += "  ...de esos, timbrados  : " + cValToChar(nTim) + CRLF
	cRet += "  ...de esos, _ORIGIN    : " + cValToChar(nOri) + CRLF + CRLF

	If nHay == 0
		cRet += "Ningun XML del servidor contiene ese texto." + CRLF
		Return cRet
	EndIf

	// Esta es la lectura que importa: un nodo que solo aparece en
	// archivos sin timbre no le falta al visor, porque esos
	// comprobantes nunca entran a las tablas.
	If nTim == 0
		cRet += "NINGUNO de estos esta timbrado. Los comprobantes sin" + CRLF
		cRet += "timbre no entran al visor, asi que no falta codigo:" + CRLF
		cRet += "ese nodo no existe en el acervo bueno." + CRLF + CRLF
	EndIf

	cRet += cLis

Return cRet
