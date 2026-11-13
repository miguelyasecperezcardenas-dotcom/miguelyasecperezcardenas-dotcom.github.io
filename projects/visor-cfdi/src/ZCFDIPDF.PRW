#INCLUDE "PROTHEUS.CH"
#INCLUDE "TOPCONN.CH"

/*/{Protheus.doc} ZCFDIPDF
Abre la representacion impresa (PDF) del comprobante seleccionado.

DE DONDE SALE EL PDF

De ningun lado: se BUSCA. Esta rutina no genera el PDF -- lo localiza,
lo baja a la maquina del usuario y se lo entrega a Windows para que lo
abra con el lector que tenga.

Generar la representacion impresa es harina de otro costal: lleva
logotipo, cadena original, sello, codigo QR y un formato que el SAT
revisa. Eso lo produce el PAC o el propio Protheus al timbrar, y
reinventarlo aqui seria hacer un PDF que se parece a una factura sin
serlo.

DONDE BUSCA, Y EN QUE ORDEN

Del comprobante se conocen dos cosas: ZCF_RUTA (la carpeta de donde se
importo su XML) y ZCF_ARCHIV (el nombre del archivo). Con eso se prueban,
en orden:

  1. El mismo nombre con extension .pdf, en la MISMA carpeta.
     Es lo mas comun: el PAC deja los dos juntos.
  2. El mismo nombre, en una subcarpeta PDF\ de esa carpeta.
  3. El mismo nombre, en una carpeta PDF\ hermana (al lado de la del XML).
  4. El folio fiscal como nombre: <uuid>.pdf, en las tres de arriba.
     Algunos PAC nombran el PDF por UUID aunque el XML tenga otro nombre.

La primera que exista, gana.

SI NO ENCUENTRA NADA

No se queda en "no se pudo". Recorre las carpetas de CFD del servidor
contando cuantos PDF hay en total, y lo reporta. Esa cuenta contesta la
pregunta de fondo -- si el problema es que este comprobante no tiene su
PDF, o que en esta instalacion no se guardan PDF -- y son dos problemas
con soluciones distintas.

@author Claude + Miguel Yasec
@since 09/2026
/*/
User Function ZCFDIPDF()
	Local cSrv := ""
	Local aVis := {}

	If Select("ZCF") == 0 .Or. Empty(ZCF->ZCF_UUID)
		MsgStop("No hay un comprobante seleccionado.", "ZCFDIPDF")
		Return
	EndIf

	cSrv := PdfBusca(@aVis)

	If Empty(cSrv)
		PdfNoHay(aVis)
		Return
	EndIf

	PdfAbre(cSrv)

Return

// ---------------------------------------------------------------------
// Devuelve la ruta en el SERVIDOR del PDF, o "" si no hay.
// En aVis deja la lista de lo que se intento, para poder decirlo.
// ---------------------------------------------------------------------
Static Function PdfBusca(aVis)
	Local cRuta := AllTrim(ZCF->ZCF_RUTA)
	Local cArch := AllTrim(ZCF->ZCF_ARCHIV)
	Local cUuid := AllTrim(ZCF->ZCF_UUID)
	Local cBase := ""
	Local aCar  := {}
	Local aNom  := {}
	Local nI    := 0
	Local nJ    := 0
	Local cTry  := ""

	aVis := {}

	If Empty(cRuta)
		Return ""
	EndIf

	// La carpeta siempre termina en diagonal. Si no, todo lo que se
	// arme abajo queda pegado al nombre de la carpeta y no existe nada.
	If Right(cRuta, 1) != "\"
		cRuta += "\"
	EndIf

	// El nombre sin extension. Se corta por el ULTIMO punto, no por el
	// primero: hay PAC que ponen puntos en medio del nombre.
	cBase := cArch
	If RAt(".", cBase) > 0
		cBase := Left(cBase, RAt(".", cBase) - 1)
	EndIf

	aCar := {cRuta, ;
	         cRuta + "PDF\", ;
	         PdfHerm(cRuta)}

	aNom := {cBase, cUuid}

	For nI := 1 To Len(aCar)
		If Empty(aCar[nI])
			Loop
		EndIf
		For nJ := 1 To Len(aNom)
			If Empty(aNom[nJ])
				Loop
			EndIf
			cTry := aCar[nI] + aNom[nJ] + ".pdf"
			aAdd(aVis, cTry)
			If File(cTry)
				Return cTry
			EndIf
		Next nJ
	Next nI

	// ULTIMO RECURSO: BARRER TODAS LAS CARPETAS DE CFD
	//
	// Las rutas de arriba suponen que el PDF esta al lado de su XML.
	// No siempre. El caso que lo destapo: un comprobante cancelado, cuyo
	// XML esta en \CFD\ANULADAS\ y cuyo PDF se quedo en la carpeta
	// normal -- el PAC genera la representacion impresa al timbrar y no
	// la vuelve a mover cuando el comprobante se cancela despues.
	//
	// Asi que si no aparecio donde deberia, se busca donde sea. Son 83
	// archivos en 8 carpetas: barrerlos cuesta menos que adivinar.
	//
	// Se compara por CONTENIDO del nombre, no por igualdad: hay PAC que
	// le pegan prefijos o sufijos al folio. Basta con que el nombre
	// traiga el folio fiscal o el nombre base del XML.
Return PdfBarre(aNom, @aVis)

// ---------------------------------------------------------------------
Static Function PdfBarre(aNom, aVis)
	Local aCar := {}
	Local aArq := {}
	Local nI   := 0
	Local nJ   := 0
	Local nK   := 0
	Local cNom := ""

	PdfAnda("\", 1, @aCar)

	aAdd(aVis, "...y " + cValToChar(Len(aCar)) + " carpeta(s) de CFD por nombre")

	For nI := 1 To Len(aCar)
		aArq := Directory(aCar[nI] + "*.pdf")
		For nJ := 1 To Len(aArq)
			cNom := Upper(AllTrim(aArq[nJ][1]))
			For nK := 1 To Len(aNom)
				If !Empty(aNom[nK]) .And. Upper(AllTrim(aNom[nK])) $ cNom
					Return aCar[nI] + AllTrim(aArq[nJ][1])
				EndIf
			Next nK
		Next nJ
	Next nI

Return ""

// ---------------------------------------------------------------------
// La carpeta PDF hermana: se sube un nivel y se baja a PDF.
//   \system\cfd\facturas\   ->   \system\cfd\PDF\
// ---------------------------------------------------------------------
Static Function PdfHerm(cRuta)
	Local cPad := cRuta
	Local nPos := 0

	// quitar la diagonal final para que RAt encuentre la anterior
	If Right(cPad, 1) == "\"
		cPad := Left(cPad, Len(cPad) - 1)
	EndIf

	nPos := RAt("\", cPad)

	If nPos == 0
		Return ""
	EndIf

Return Left(cPad, nPos) + "PDF\"

// ---------------------------------------------------------------------
// Lo baja a la maquina del usuario y se lo pasa a Windows.
//
// NO se intenta abrir el PDF desde el servidor: el lector corre en la
// maquina del usuario y esa ruta no existe para el. Hay que copiarlo
// primero.
//
// OJO CON CpyS2T: el destino es una CARPETA, no la ruta completa del
// archivo. Pasarle "C:\algo.pdf" responde "Directory c:\algo.pdf\ does
// not exist", que suena a otra cosa. Es el mismo tropiezo que ya esta
// documentado en ZCFDIEXP.
// ---------------------------------------------------------------------
Static Function PdfAbre(cSrv)
	Local aCar := {"C:\TOTVS\", "C:\Temp\", "C:\"}
	Local cNom := ""
	Local cCli := ""
	Local nI   := 0

	cNom := SubStr(cSrv, RAt("\", cSrv) + 1)

	For nI := 1 To Len(aCar)
		If CpyS2T(cSrv, aCar[nI], .T.)
			cCli := aCar[nI] + cNom
			Exit
		EndIf
	Next nI

	If Empty(cCli)
		MsgStop("El PDF existe en el servidor pero no se pudo copiar" + CRLF + ;
			"a tu maquina." + CRLF + CRLF + ;
			"Se intento en: C:\TOTVS\ , C:\Temp\ , C:\" + CRLF + CRLF + ;
			"Esta en el servidor, en:" + CRLF + cSrv, "ZCFDIPDF")
		Return
	EndIf

	// El 1 del final es SW_SHOWNORMAL: que la ventana se vea. Con 0 el
	// lector abre escondido y parece que no paso nada.
	ShellExecute("open", cCli, "", "C:\", 1)

Return

// ---------------------------------------------------------------------
// No se encontro. Se dice donde se busco, y cuantos PDF hay en todo
// el servidor -- que es el dato que de verdad sirve.
// ---------------------------------------------------------------------
Static Function PdfNoHay(aVis)
	Local cMsg := ""
	Local nI   := 0
	Local nTot := 0
	Local nCar := 0

	nTot := PdfCuenta(@nCar)

	cMsg := "No se encontro el PDF de este comprobante." + CRLF + CRLF
	cMsg += "Se busco en:" + CRLF
	For nI := 1 To Len(aVis)
		cMsg += "  " + aVis[nI] + CRLF
	Next nI

	cMsg += CRLF + "EN TODO EL SERVIDOR:" + CRLF
	cMsg += "  Carpetas de CFD revisadas : " + cValToChar(nCar) + CRLF
	cMsg += "  Archivos PDF encontrados  : " + cValToChar(nTot) + CRLF + CRLF

	If nTot == 0
		cMsg += "NO HAY UN SOLO PDF en las carpetas de CFD." + CRLF + CRLF
		cMsg += "Entonces no es que a este comprobante le falte el suyo:" + CRLF
		cMsg += "en esta instalacion no se estan guardando los PDF." + CRLF + CRLF
		cMsg += "La representacion impresa la genera el PAC al timbrar." + CRLF
		cMsg += "Hay que pedirle a quien administra EDICOM que los deje" + CRLF
		cMsg += "junto a los XML, o bajarlos de su portal. Generarlos" + CRLF
		cMsg += "aqui no es opcion: llevan sello, cadena original y QR."
	Else
		cMsg += "SI hay PDF en el servidor, pero ninguno menciona el" + CRLF
		cMsg += "nombre del XML ni el folio fiscal de este comprobante." + CRLF + CRLF
		cMsg += "Asi se llaman algunos de los que si hay:" + CRLF
		cMsg += PdfMuestra()
		cMsg += CRLF + "Con ver ese patron se ajusta la busqueda."
	EndIf

	MsgStop(cMsg, "ZCFDIPDF")

Return

// ---------------------------------------------------------------------
// Unos cuantos nombres de PDF reales, para aprender como los nombra el
// PAC. Es la unica forma de ajustar la busqueda sin adivinar.
// ---------------------------------------------------------------------
Static Function PdfMuestra()
	Local aCar := {}
	Local aArq := {}
	Local cRet := ""
	Local nI   := 0
	Local nJ   := 0
	Local nN   := 0

	PdfAnda("\", 1, @aCar)

	For nI := 1 To Len(aCar)
		aArq := Directory(aCar[nI] + "*.pdf")
		For nJ := 1 To Len(aArq)
			nN++
			cRet += "  " + aCar[nI] + AllTrim(aArq[nJ][1]) + CRLF
			If nN >= 5
				Return cRet
			EndIf
		Next nJ
	Next nI

Return cRet

// ---------------------------------------------------------------------
// Cuenta los PDF que hay en las carpetas de CFD del servidor.
//
// Se recorre igual que el importador busca XML: por carpetas cuyo
// nombre traiga "CFD", bajando hasta cuatro niveles. Asi se mira en
// los mismos lugares y la respuesta es comparable.
// ---------------------------------------------------------------------
Static Function PdfCuenta(nCar)
	Local aCar := {}
	Local nTot := 0
	Local nI   := 0

	PdfAnda("\", 1, @aCar)

	nCar := Len(aCar)

	For nI := 1 To Len(aCar)
		nTot += Len(Directory(aCar[nI] + "*.pdf"))
	Next nI

Return nTot

// ---------------------------------------------------------------------
Static Function PdfAnda(cRuta, nNiv, aCar)
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

			If "CFD" $ Upper(cSub)
				aAdd(aCar, cSub)
			EndIf

			PdfAnda(cSub, nNiv + 1, @aCar)
		EndIf
	Next nI

Return
