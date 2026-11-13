#INCLUDE "PROTHEUS.CH"
#INCLUDE "TOPCONN.CH"

/*/{Protheus.doc} ZCFDICAT
Catalogos del SAT para el visor de CFDI.

El XML guarda claves, no descripciones: dice "03" y no "Transferencia
electronica de fondos", dice "601" y no "General de Ley Personas
Morales". Las contadoras pidieron ver las descripciones, y de ahi sale
esta tabla.

UNA SOLA TABLA PARA TODOS LOS CATALOGOS

ZCT guarda cualquier catalogo: el nombre del catalogo es parte de la
llave. Asi agregar uno nuevo no necesita ni tabla nueva ni campo nuevo,
solo renglones.

  ZCT_CATALO   c_FormaPago, c_RegimenFiscal, c_ClaveProdServ...
  ZCT_CLAVE    03, 601, 01010101...
  ZCT_DESCRI   la descripcion que se muestra

DOS ORIGENES

  1. Los catalogos CHICOS vienen escritos en este fuente (CatBase).
     Son los de 2 a 25 renglones que casi nunca cambian: formas de
     pago, metodos, regimenes, uso del CFDI. Cargarlos no necesita
     archivo ni internet, y con eso el visor ya muestra descripciones
     desde el primer dia.

  2. Los catalogos GRANDES se importan de un CSV (CatCsv). Son dos:
     c_ClaveProdServ con unas 52,000 claves y c_ClaveUnidad con 2,400.
     Escribirlos aqui seria absurdo y ademas el SAT los actualiza.

El mismo mecanismo de CSV sirve para reemplazar cualquier catalogo
chico cuando el SAT publique una version nueva: se importa encima y
gana el archivo.

POR QUE HAY CACHE

El browse del visor pinta miles de renglones y por cada uno pediria la
descripcion de la forma de pago, del metodo, del regimen. Si cada una
fuera un seek contra la base, el visor se arrastraria.

CatDesc carga el catalogo completo a memoria la primera vez que se le
pide algo de el, y de ahi en adelante responde sin tocar la base. Los
catalogos chicos caben de sobra. c_ClaveProdServ NO se cachea completo
por su tamano: ese va por seek, pero solo se pide en el detalle de un
comprobante, no en el browse.

@author Claude + Miguel Yasec
@since 09/2026
/*/

// Cache en memoria. Se llena solo, la primera vez que se pide cada
// catalogo. Vive mientras viva la sesion.
Static _aCache := {}

// ---------------------------------------------------------------------
// TRES OPCIONES, NO CUATRO
//
// Aviso() admite un maximo de TRES botones. Con cuatro no truena pero
// esconde las tres primeras dentro de un desplegable "Otras acciones",
// que es peor que tronar porque parece que funciona.
//
// Crear la tabla y cargar los catalogos van juntos en la misma opcion:
// nadie crea la tabla para dejarla vacia, y separarlos solo servia para
// que alguien hiciera la mitad del trabajo y creyera que termino.
// ---------------------------------------------------------------------
User Function ZCFDICAT()
	Local aOpc := {"1. Crear y cargar", ;
	               "2. Importar un CSV", ;
	               "3. Ver que hay cargado"}
	Local nOpc := 0

	While .T.
		nOpc := Aviso("ZCFDICAT - Catalogos del SAT", ;
			"Las descripciones que el XML no trae." + CRLF + CRLF + ;
			"1. Crear y cargar : deja listos los catalogos chicos" + CRLF + ;
			"                    (forma de pago, regimen, uso CFDI...)" + CRLF + ;
			"2. Importar CSV   : para los grandes -- clave de producto" + CRLF + ;
			"                    y clave de unidad" + CRLF + ;
			"3. Ver que hay    : cuantas claves quedaron cargadas" + CRLF + CRLF + ;
			"Empieza por la 1. Se puede repetir sin duplicar." + CRLF + CRLF + ;
			"Para salir, cierra la ventana.", ;
			aOpc, 3)

		Do Case
		Case nOpc == 1
			CatTodo()
		Case nOpc == 2
			CatCsv()
		Case nOpc == 3
			CatVer()
		Otherwise
			Exit
		EndCase
	EndDo

Return

// ---------------------------------------------------------------------
// Crear la tabla y cargar los catalogos, en un solo paso.
//
// Si la tabla ya existe no se vuelve a crear y se pasa derecho a
// cargar: correrlo dos veces no hace dano.
// ---------------------------------------------------------------------
Static Function CatTodo()
	Local cFis := CatFis("ZCT")

	If !CatHayTb(cFis)
		If !CatCrea()
			Return
		EndIf
	EndIf

	CatCarga()

Return

// ---------------------------------------------------------------------
// LA TABLA
//
// Se crea aqui y no en ZCFDIDIC a proposito: ese fuente ya esta
// entregado para compilar en produccion y no se quiere mover. Este
// archivo es nuevo y se basta solo.
// ---------------------------------------------------------------------
Static Function CatDef()
Return {"ZCT", "Visor CFDI - Catalogos SAT", ;
	{"ZCT_FILIAL", "ZCT_CATALO", "ZCT_CLAVE"}, {;
	{"ZCT_FILIAL", "C",   2, 0, "Sucursal"      }, ;
	{"ZCT_CATALO", "C",  20, 0, "Catalogo"      }, ;
	{"ZCT_CLAVE",  "C",  25, 0, "Clave"         }, ;
	{"ZCT_DESCRI", "C", 250, 0, "Descripcion"   }, ;
	{"ZCT_DATO1",  "C",  60, 0, "Dato adicional"}, ;
	{"ZCT_FECACT", "D",   8, 0, "Actualizado"   }  ;
	}}

// ---------------------------------------------------------------------
// Devuelve .T. si la tabla quedo lista -- sea porque ya estaba o
// porque se acaba de crear. CatTodo lo usa para saber si sigue.
Static Function CatCrea()
	Local aTab := CatDef()
	Local cFis := CatFis("ZCT")
	Local cMsg := ""

	If CatHayTb(cFis)
		Return .T.
	EndIf

	If !MsgYesNo("La tabla ZCT (" + cFis + ") no existe todavia." + CRLF + ;
		"Se va a crear con " + cValToChar(Len(aTab[4])) + " campos," + CRLF + ;
		"y enseguida se cargan los catalogos." + CRLF + CRLF + ;
		"CREAR AHORA?", "ZCFDICAT")
		Return .F.
	EndIf

	cMsg := CatTabla(aTab)
	MsgInfo(cMsg, "ZCFDICAT - tabla creada")

Return CatHayTb(cFis)

// ---------------------------------------------------------------------
// Crea la tabla fisica y la da de alta en SX2, SX3 y SIX.
// Es el mismo procedimiento de ZCFDIDIC, recortado a una sola tabla.
// ---------------------------------------------------------------------
Static Function CatTabla(aTab)
	Local cAli  := aTab[1]
	Local cNom  := aTab[2]
	Local aLlav := aTab[3]
	Local aCpo  := aTab[4]
	Local cFis  := CatFis(cAli)
	Local cMsg  := "== " + cAli + " (" + cFis + ") ==" + CRLF
	Local cCols := ""
	Local cChav := ""
	Local cSql  := ""
	Local nRet  := 0
	Local nI    := 0

	For nI := 1 To Len(aLlav)
		If nI > 1
			cChav += "+"
			cCols += ", "
		EndIf
		cChav += aLlav[nI]
		cCols += aLlav[nI]
	Next nI

	// ---------- tabla fisica ----------
	cSql := "CREATE TABLE " + cFis + " ("
	For nI := 1 To Len(aCpo)
		If nI > 1
			cSql += ", "
		EndIf
		cSql += aCpo[nI][1] + " " + CatTipo(aCpo[nI])
	Next nI
	cSql += ", D_E_L_E_T_ CHAR(1) DEFAULT ' ' NOT NULL"
	cSql += ", R_E_C_N_O_ NUMBER(22) DEFAULT 0 NOT NULL"
	cSql += ", R_E_C_D_E_L_ NUMBER(22) DEFAULT 0 NOT NULL"
	cSql += ")"

	nRet := TCSQLExec(cSql)
	cMsg += "  CREATE TABLE: " + IIf(nRet < 0, "ERROR " + TCSQLError(), "OK") + CRLF
	If nRet < 0
		Return cMsg
	EndIf

	nRet := TCSQLExec("CREATE INDEX " + cFis + "1 ON " + cFis + ;
		" (" + cCols + ", R_E_C_N_O_, D_E_L_E_T_)")
	cMsg += "  indice de orden 1: " + IIf(nRet < 0, "ERROR", "OK") + CRLF

	nRet := TCSQLExec("CREATE UNIQUE INDEX " + cFis + "_PK ON " + cFis + " (R_E_C_N_O_)")
	cMsg += "  indice _PK: " + IIf(nRet < 0, "ERROR", "OK") + CRLF

	nRet := TCSQLExec("CREATE UNIQUE INDEX " + cFis + "_UNQ ON " + cFis + ;
		" (" + cCols + ", R_E_C_D_E_L_)")
	cMsg += "  indice _UNQ: " + IIf(nRet < 0, "ERROR", "OK") + CRLF

	cMsg += CatSX2(cAli, cFis, cNom, cChav)
	cMsg += CatSX3(cAli, aCpo)
	cMsg += CatSIX(cAli, cChav)

Return cMsg

// ---------------------------------------------------------------------
Static Function CatTipo(aCpo)
	Local cRet := ""

	Do Case
	Case aCpo[2] == "D"
		cRet := "CHAR(8) DEFAULT ' ' NOT NULL"
	Case aCpo[2] == "N"
		cRet := "NUMBER(" + cValToChar(aCpo[3]) + "," + ;
			cValToChar(aCpo[4]) + ") DEFAULT 0 NOT NULL"
	Otherwise
		cRet := "CHAR(" + cValToChar(aCpo[3]) + ") DEFAULT ' ' NOT NULL"
	EndCase

Return cRet

// ---------------------------------------------------------------------
Static Function CatFis(cAli)
Return AllTrim(cAli) + SubStr(AllTrim(RetSqlName("SF2")), 4)

// ---------------------------------------------------------------------
Static Function CatHayTb(cFis)
	Local nRet := 0

	BeginSql Alias "QT"
		SELECT COUNT(*) AS TOT FROM ALL_TABLES WHERE TABLE_NAME = %Exp:cFis%
	EndSql
	QT->(DbGoTop())
	nRet := QT->TOT
	QT->(DbCloseArea())

Return nRet > 0

// ---------------------------------------------------------------------
Static Function CatSX2(cAli, cFis, cNom, cChav)
	Local aVals := {}
	Local nI    := 0

	If Select("SX2") == 0
		ChkFile("SX2")
	EndIf
	If Select("SX2") == 0
		Return "  [!!] no se pudo abrir SX2" + CRLF
	EndIf

	SX2->(DbSetOrder(1))
	If !SX2->(MsSeek("ZA1"))
		Return "  [!!] no esta ZA1 en SX2 para usar de molde" + CRLF
	EndIf

	For nI := 1 To SX2->(FCount())
		aAdd(aVals, SX2->(FieldGet(nI)))
	Next nI

	If SX2->(MsSeek(cAli))
		Return "  SX2: ya existia" + CRLF
	EndIf

	RecLock("SX2", .T.)
	For nI := 1 To SX2->(FCount())
		SX2->(FieldPut(nI, aVals[nI]))
	Next nI
	SX2->X2_CHAVE   := cAli
	SX2->X2_ARQUIVO := cFis
	SX2->X2_NOME    := cNom
	SX2->X2_NOMESPA := cNom
	SX2->X2_NOMEENG := cNom
	SX2->X2_UNICO   := cChav

	CatPon("SX2", "X2_MODO",    "C")
	CatPon("SX2", "X2_MODOUN",  "C")
	CatPon("SX2", "X2_MODOEMP", "C")

	SX2->(MsUnlock())

Return "  SX2: creado (modos en Compartido)" + CRLF

// ---------------------------------------------------------------------
Static Function CatPon(cAlias, cCampo, xVal)
	Local nPos := (cAlias)->(FieldPos(cCampo))

	If nPos > 0
		(cAlias)->(FieldPut(nPos, xVal))
	EndIf

Return

// ---------------------------------------------------------------------
Static Function CatSX3(cAli, aCpo)
	Local aMolC := {}
	Local aMolD := {}
	Local nI    := 0
	Local nJ    := 0
	Local nNue  := 0

	If Select("SX3") == 0
		ChkFile("SX3")
	EndIf
	If Select("SX3") == 0
		Return "  [!!] no se pudo abrir SX3" + CRLF
	EndIf

	SX3->(DbSetOrder(1))
	If SX3->(MsSeek("ZA1"))
		While !SX3->(Eof()) .And. AllTrim(SX3->X3_ARQUIVO) == "ZA1"
			If AllTrim(SX3->X3_CAMPO) == "ZA1_DESC"
				aMolC := {}
				For nJ := 1 To SX3->(FCount())
					aAdd(aMolC, SX3->(FieldGet(nJ)))
				Next nJ
			EndIf
			If AllTrim(SX3->X3_CAMPO) == "ZA1_DTINI"
				aMolD := {}
				For nJ := 1 To SX3->(FCount())
					aAdd(aMolD, SX3->(FieldGet(nJ)))
				Next nJ
			EndIf
			SX3->(DbSkip())
		EndDo
	EndIf

	If Len(aMolC) == 0 .Or. Len(aMolD) == 0
		Return "  [!!] no estan los campos molde de ZA1 en SX3" + CRLF
	EndIf

	For nI := 1 To Len(aCpo)
		If CatHayCp(cAli, aCpo[nI][1])
			Loop
		EndIf

		RecLock("SX3", .T.)

		If aCpo[nI][2] == "D"
			For nJ := 1 To SX3->(FCount())
				SX3->(FieldPut(nJ, aMolD[nJ]))
			Next nJ
		Else
			For nJ := 1 To SX3->(FCount())
				SX3->(FieldPut(nJ, aMolC[nJ]))
			Next nJ
		EndIf

		SX3->X3_ARQUIVO := cAli
		SX3->X3_ORDEM   := StrZero(nI, 2)
		SX3->X3_CAMPO   := aCpo[nI][1]
		SX3->X3_TIPO    := aCpo[nI][2]
		SX3->X3_TAMANHO := aCpo[nI][3]
		SX3->X3_DECIMAL := aCpo[nI][4]
		SX3->X3_TITULO  := aCpo[nI][5]
		SX3->X3_TITSPA  := aCpo[nI][5]
		SX3->X3_TITENG  := aCpo[nI][5]

		CatPon("SX3", "X3_BROWSE",  "N")
		CatPon("SX3", "X3_DESCRIC", aCpo[nI][5])
		CatPon("SX3", "X3_DESCSPA", aCpo[nI][5])
		CatPon("SX3", "X3_DESCENG", aCpo[nI][5])

		SX3->(MsUnlock())
		nNue++
	Next nI

Return "  SX3: " + cValToChar(nNue) + " campos nuevos" + CRLF

// ---------------------------------------------------------------------
Static Function CatHayCp(cAli, cCampo)
	Local nRet := 0
	Local cSql := ""

	cSql := "SELECT COUNT(*) AS TOT FROM " + CatFis("SX3") + " "
	cSql += "WHERE D_E_L_E_T_ = ' ' "
	cSql += "AND TRIM(X3_ARQUIVO) = '" + AllTrim(cAli) + "' "
	cSql += "AND TRIM(X3_CAMPO) = '" + AllTrim(cCampo) + "'"

	TCQuery cSql New Alias "QC"
	QC->(DbGoTop())
	nRet := QC->TOT
	QC->(DbCloseArea())

Return nRet > 0

// ---------------------------------------------------------------------
Static Function CatSIX(cAli, cChav)
	Local nHay := 0
	Local nRet := 0
	Local cFis := CatFis("SIX")
	Local cSql := ""

	cSql := "SELECT COUNT(*) AS TOT FROM " + cFis + ;
		" WHERE TRIM(INDICE) = '" + AllTrim(cAli) + "'"

	TCQuery cSql New Alias "QS"
	QS->(DbGoTop())
	nHay := QS->TOT
	QS->(DbCloseArea())

	If nHay > 0
		Return "  SIX: ya existia" + CRLF
	EndIf

	nRet := TCSQLExec("INSERT INTO " + cFis + ;
		" (INDICE, ORDEM, CHAVE, DESCRICAO, DESCSPA, DESCENG, " + ;
		"PROPRI, F3, NICKNAME, SHOWPESQ, D_E_L_E_T_, R_E_C_N_O_, R_E_C_D_E_L_) " + ;
		"SELECT '" + cAli + "', '1', '" + cChav + "', 'Clave unica', 'Clave unica', " + ;
		"'Unique key', 'U', ' ', '" + cAli + "001', 'N', ' ', " + ;
		"(SELECT MAX(R_E_C_N_O_)+1 FROM " + cFis + "), 0 FROM DUAL")

Return "  SIX: " + IIf(nRet < 0, "ERROR " + TCSQLError(), "OK") + CRLF

// =====================================================================
// LOS CATALOGOS CHICOS
//
// Vigentes al 09/2026. Si el SAT publica una version nueva no hay que
// tocar este fuente: se importa el CSV encima con la opcion 2 y gana
// el archivo.
// =====================================================================
Static Function CatBase()
	Local aRet := {}

	// ---------- c_TipoDeComprobante ----------
	aAdd(aRet, {"c_TipoDeComprobante", {;
		{"I", "Ingreso"   }, ;
		{"E", "Egreso"    }, ;
		{"T", "Traslado"  }, ;
		{"N", "Nomina"    }, ;
		{"P", "Pago"      }  ;
		}})

	// ---------- c_MetodoPago ----------
	aAdd(aRet, {"c_MetodoPago", {;
		{"PUE", "Pago en una sola exhibicion"     }, ;
		{"PPD", "Pago en parcialidades o diferido"}  ;
		}})

	// ---------- c_FormaPago ----------
	aAdd(aRet, {"c_FormaPago", {;
		{"01", "Efectivo"                           }, ;
		{"02", "Cheque nominativo"                  }, ;
		{"03", "Transferencia electronica de fondos"}, ;
		{"04", "Tarjeta de credito"                 }, ;
		{"05", "Monedero electronico"               }, ;
		{"06", "Dinero electronico"                 }, ;
		{"08", "Vales de despensa"                  }, ;
		{"12", "Dacion en pago"                     }, ;
		{"13", "Pago por subrogacion"               }, ;
		{"14", "Pago por consignacion"              }, ;
		{"15", "Condonacion"                        }, ;
		{"17", "Compensacion"                       }, ;
		{"23", "Novacion"                           }, ;
		{"24", "Confusion"                          }, ;
		{"25", "Remision de deuda"                  }, ;
		{"26", "Prescripcion o caducidad"           }, ;
		{"27", "A satisfaccion del acreedor"        }, ;
		{"28", "Tarjeta de debito"                  }, ;
		{"29", "Tarjeta de servicios"               }, ;
		{"30", "Aplicacion de anticipos"            }, ;
		{"31", "Intermediario pagos"                }, ;
		{"99", "Por definir"                        }  ;
		}})

	// ---------- c_Impuesto ----------
	aAdd(aRet, {"c_Impuesto", {;
		{"001", "ISR" }, ;
		{"002", "IVA" }, ;
		{"003", "IEPS"}  ;
		}})

	// ---------- c_TipoFactor ----------
	aAdd(aRet, {"c_TipoFactor", {;
		{"Tasa",   "Tasa"  }, ;
		{"Cuota",  "Cuota" }, ;
		{"Exento", "Exento"}  ;
		}})

	// ---------- c_ObjetoImp ----------
	aAdd(aRet, {"c_ObjetoImp", {;
		{"01", "No objeto de impuesto"                          }, ;
		{"02", "Si objeto de impuesto"                          }, ;
		{"03", "Si objeto del impuesto y no obligado al desglose"}, ;
		{"04", "Si objeto del impuesto y no causa impuesto"     }, ;
		{"05", "Si objeto del impuesto, IVA credito PODEBI"     }, ;
		{"06", "Si objeto del IVA, No traslado IVA"             }, ;
		{"07", "No traslado del IVA, Si desglose IEPS"          }, ;
		{"08", "No traslado del IVA, No desglose IEPS"          }  ;
		}})

	// ---------- c_Exportacion ----------
	aAdd(aRet, {"c_Exportacion", {;
		{"01", "No aplica"                                        }, ;
		{"02", "Definitiva con clave de pedimento A1"             }, ;
		{"03", "Temporal"                                         }, ;
		{"04", "Definitiva con clave distinta a A1 o cuando no existe enajenacion"} ;
		}})

	// ---------- c_TipoRelacion ----------
	aAdd(aRet, {"c_TipoRelacion", {;
		{"01", "Nota de credito de los documentos relacionados"       }, ;
		{"02", "Nota de debito de los documentos relacionados"        }, ;
		{"03", "Devolucion de mercancia sobre facturas o traslados previos"}, ;
		{"04", "Sustitucion de los CFDI previos"                      }, ;
		{"05", "Traslados de mercancias facturados previamente"       }, ;
		{"06", "Factura generada por los traslados previos"           }, ;
		{"07", "CFDI por aplicacion de anticipo"                      }  ;
		}})

	// ---------- c_RegimenFiscal ----------
	aAdd(aRet, {"c_RegimenFiscal", {;
		{"601", "General de Ley Personas Morales"                     }, ;
		{"603", "Personas Morales con Fines no Lucrativos"            }, ;
		{"605", "Sueldos y Salarios e Ingresos Asimilados a Salarios" }, ;
		{"606", "Arrendamiento"                                       }, ;
		{"607", "Regimen de Enajenacion o Adquisicion de Bienes"      }, ;
		{"608", "Demas ingresos"                                      }, ;
		{"610", "Residentes en el Extranjero sin Establecimiento Permanente en Mexico"}, ;
		{"611", "Ingresos por Dividendos (socios y accionistas)"      }, ;
		{"612", "Personas Fisicas con Actividades Empresariales y Profesionales"}, ;
		{"614", "Ingresos por intereses"                              }, ;
		{"615", "Regimen de los ingresos por obtencion de premios"    }, ;
		{"616", "Sin obligaciones fiscales"                           }, ;
		{"620", "Sociedades Cooperativas de Produccion que optan por diferir sus ingresos"}, ;
		{"621", "Incorporacion Fiscal"                                }, ;
		{"622", "Actividades Agricolas, Ganaderas, Silvicolas y Pesqueras"}, ;
		{"623", "Opcional para Grupos de Sociedades"                  }, ;
		{"624", "Coordinados"                                         }, ;
		{"625", "Regimen de las Actividades Empresariales con ingresos a traves de Plataformas Tecnologicas"}, ;
		{"626", "Regimen Simplificado de Confianza"                   }  ;
		}})

	// ---------- c_UsoCFDI ----------
	aAdd(aRet, {"c_UsoCFDI", {;
		{"G01",  "Adquisicion de mercancias"                    }, ;
		{"G02",  "Devoluciones, descuentos o bonificaciones"    }, ;
		{"G03",  "Gastos en general"                            }, ;
		{"I01",  "Construcciones"                               }, ;
		{"I02",  "Mobiliario y equipo de oficina por inversiones"}, ;
		{"I03",  "Equipo de transporte"                         }, ;
		{"I04",  "Equipo de computo y accesorios"               }, ;
		{"I05",  "Dados, troqueles, moldes, matrices y herramental"}, ;
		{"I06",  "Comunicaciones telefonicas"                   }, ;
		{"I07",  "Comunicaciones satelitales"                   }, ;
		{"I08",  "Otra maquinaria y equipo"                     }, ;
		{"D01",  "Honorarios medicos, dentales y gastos hospitalarios"}, ;
		{"D02",  "Gastos medicos por incapacidad o discapacidad"}, ;
		{"D03",  "Gastos funerales"                             }, ;
		{"D04",  "Donativos"                                    }, ;
		{"D05",  "Intereses reales efectivamente pagados por creditos hipotecarios"}, ;
		{"D06",  "Aportaciones voluntarias al SAR"              }, ;
		{"D07",  "Primas por seguros de gastos medicos"         }, ;
		{"D08",  "Gastos de transportacion escolar obligatoria" }, ;
		{"D09",  "Depositos en cuentas para el ahorro, primas que tengan como base planes de pensiones"}, ;
		{"D10",  "Pagos por servicios educativos (colegiaturas)"}, ;
		{"S01",  "Sin efectos fiscales"                         }, ;
		{"CP01", "Pagos"                                        }, ;
		{"CN01", "Nomina"                                       }  ;
		}})

Return aRet

// ---------------------------------------------------------------------
// Carga los catalogos chicos. Se puede correr las veces que sea: lo
// que ya esta se actualiza, no se duplica.
// ---------------------------------------------------------------------
Static Function CatCarga()
	Local aCats := CatBase()
	Local nTot  := 0
	Local nI    := 0

	For nI := 1 To Len(aCats)
		nTot += Len(aCats[nI][2])
	Next nI

	If !MsgYesNo("Se van a cargar " + cValToChar(Len(aCats)) + " catalogos" + CRLF + ;
		"con " + cValToChar(nTot) + " claves en total." + CRLF + CRLF + ;
		"Lo que ya este cargado se actualiza." + CRLF + CRLF + ;
		"CARGAR AHORA?", "ZCFDICAT")
		Return
	EndIf

	Processa({|| CatGraba(aCats) }, "Cargando catalogos...")

Return

// ---------------------------------------------------------------------
Static Function CatGraba(aCats)
	Local cMsg := "CATALOGOS CARGADOS" + CRLF + CRLF
	Local nNue := 0
	Local nAct := 0
	Local nI   := 0
	Local nJ   := 0
	Local nN   := 0
	Local nA   := 0

	If Select("ZCT") == 0
		ChkFile("ZCT")
	EndIf
	If Select("ZCT") == 0
		MsgStop("No se pudo abrir ZCT. Corre primero la opcion 1.", "ZCFDICAT")
		Return
	EndIf

	For nI := 1 To Len(aCats)
		nN := 0
		nA := 0

		For nJ := 1 To Len(aCats[nI][2])
			If CatUna(aCats[nI][1], aCats[nI][2][nJ][1], aCats[nI][2][nJ][2], "")
				nN++
			Else
				nA++
			EndIf
		Next nJ

		cMsg += "  " + PadR(aCats[nI][1], 22) + ;
			StrZero(nN, 3) + " nuevas  " + StrZero(nA, 3) + " actualizadas" + CRLF
		nNue += nN
		nAct += nA
	Next nI

	cMsg += CRLF + "Total: " + cValToChar(nNue) + " nuevas, " + ;
		cValToChar(nAct) + " actualizadas." + CRLF + CRLF
	cMsg += "Faltan los catalogos grandes (claves de producto" + CRLF
	cMsg += "y de unidad). Esos van por la opcion 2."

	_aCache := {}

	MsgInfo(cMsg, "ZCFDICAT - resultado")

Return

// ---------------------------------------------------------------------
// Graba una clave. Devuelve .T. si era nueva, .F. si ya existia y se
// actualizo.
// ---------------------------------------------------------------------
Static Function CatUna(cCat, cClave, cDesc, cDato)
	Local lNueva := .F.

	ZCT->(DbSetOrder(1))

	If ZCT->(MsSeek(xFilial("ZCT") + PadR(cCat, 20) + PadR(cClave, 25)))
		RecLock("ZCT", .F.)
	Else
		RecLock("ZCT", .T.)
		ZCT->ZCT_FILIAL := xFilial("ZCT")
		ZCT->ZCT_CATALO := cCat
		ZCT->ZCT_CLAVE  := cClave
		lNueva := .T.
	EndIf

	ZCT->ZCT_DESCRI := cDesc
	ZCT->ZCT_DATO1  := cDato

	// El campo esta definido como D en el diccionario, pero Protheus lee
	// el diccionario al ABRIR sesion: si la tabla se creo en esta misma
	// sesion, ZCT_FECACT todavia se ve como C(8) y asignarle Date()
	// truena con "Invalid data type". Escribimos segun lo que el RDD
	// este reportando en este momento.
	If ValType(ZCT->ZCT_FECACT) == "D"
		ZCT->ZCT_FECACT := Date()
	Else
		ZCT->ZCT_FECACT := DToS(Date())
	EndIf

	ZCT->(MsUnlock())

Return lNueva

// =====================================================================
// IMPORTACION DESDE CSV
//
// Para los catalogos grandes y para actualizar cualquiera cuando el SAT
// publique version nueva.
//
// FORMATO DEL ARCHIVO
//
//   clave|descripcion
//   01010101|No existe en el catalogo
//   10101500|Animales vivos de granja
//
// Separador barra vertical, sin encabezado. Se eligio la barra y no la
// coma porque las descripciones del SAT traen comas por todos lados y
// partirlas bien seria un dolor innecesario.
//
// De donde sale el archivo: el SAT publica catCFDI_V_4 en Excel. Se
// abre, se deja clave y descripcion, y se guarda como CSV cambiando el
// separador a barra.
// =====================================================================
Static Function CatCsv()
	Local cArq  := ""
	Local cCat  := ""

	cArq := cGetFile("Archivos CSV|*.csv|Todos|*.*", ;
		"Archivo del catalogo", 0, "C:\", .F., GETF_LOCALHARD, .F., .T.)

	If Empty(cArq)
		Return
	EndIf

	cCat := Space(20)
	If !CatPide(@cCat)
		Return
	EndIf
	cCat := AllTrim(cCat)

	If Empty(cCat)
		MsgStop("Hay que decir a que catalogo pertenece el archivo.", "ZCFDICAT")
		Return
	EndIf

	Processa({|| CatLee(cArq, cCat) }, "Importando " + cCat + "...")

Return

// ---------------------------------------------------------------------
// Pide el nombre del catalogo. Se escribe a mano a proposito: asi se
// puede cargar un catalogo que este fuente no conoce todavia.
// ---------------------------------------------------------------------
Static Function CatPide(cCat)
	Local oDlg  := NIL
	Local lOk   := .F.
	Local oGet  := NIL

	DEFINE MSDIALOG oDlg TITLE "Nombre del catalogo" FROM 0, 0 TO 140, 400 PIXEL

	@ 10, 10 SAY "Como se llama el catalogo?" SIZE 180, 8 OF oDlg PIXEL
	@ 22, 10 GET oGet VAR cCat SIZE 170, 10 OF oDlg PIXEL
	@ 36, 10 SAY "Ejemplos: c_ClaveProdServ, c_ClaveUnidad, c_Moneda" ;
		SIZE 180, 8 OF oDlg PIXEL

	@ 52, 60 BUTTON "Importar" SIZE 40, 12 OF oDlg PIXEL ;
		ACTION (lOk := .T., oDlg:End())
	@ 52, 105 BUTTON "Cancelar" SIZE 40, 12 OF oDlg PIXEL ;
		ACTION oDlg:End()

	ACTIVATE MSDIALOG oDlg CENTERED

Return lOk

// ---------------------------------------------------------------------
Static Function CatLee(cArq, cCat)
	Local nHdl  := 0
	Local cBuf  := ""
	Local aLin  := {}
	Local cLin  := ""
	Local nPos  := 0
	Local nNue  := 0
	Local nAct  := 0
	Local nMal  := 0
	Local nI    := 0
	Local cCla  := ""
	Local cDes  := ""

	If Select("ZCT") == 0
		ChkFile("ZCT")
	EndIf
	If Select("ZCT") == 0
		MsgStop("No se pudo abrir ZCT. Corre primero la opcion 1.", "ZCFDICAT")
		Return
	EndIf

	nHdl := FOpen(cArq, 0)
	If nHdl == -1
		MsgStop("No se pudo abrir el archivo:" + CRLF + cArq, "ZCFDICAT")
		Return
	EndIf

	cBuf := ""
	While .T.
		cLin := Space(32768)
		nPos := FRead(nHdl, @cLin, 32768)
		If nPos <= 0
			Exit
		EndIf
		cBuf += SubStr(cLin, 1, nPos)
	EndDo
	FClose(nHdl)

	// Los archivos pueden venir con fin de linea de Windows o de Unix.
	cBuf := StrTran(cBuf, Chr(13) + Chr(10), Chr(10))
	cBuf := StrTran(cBuf, Chr(13), Chr(10))
	aLin := StrTokArr(cBuf, Chr(10))

	ProcRegua(Len(aLin))

	For nI := 1 To Len(aLin)
		IncProc("Renglon " + cValToChar(nI) + " de " + cValToChar(Len(aLin)))

		cLin := AllTrim(aLin[nI])
		If Empty(cLin)
			Loop
		EndIf

		nPos := At("|", cLin)
		If nPos == 0
			nMal++
			Loop
		EndIf

		cCla := AllTrim(SubStr(cLin, 1, nPos - 1))
		cDes := AllTrim(SubStr(cLin, nPos + 1))

		If Empty(cCla)
			nMal++
			Loop
		EndIf

		If CatUna(cCat, cCla, cDes, "")
			nNue++
		Else
			nAct++
		EndIf
	Next nI

	_aCache := {}

	MsgInfo("IMPORTACION DE " + cCat + CRLF + CRLF + ;
		"  Renglones leidos:  " + cValToChar(Len(aLin)) + CRLF + ;
		"  Claves nuevas:     " + cValToChar(nNue) + CRLF + ;
		"  Actualizadas:      " + cValToChar(nAct) + CRLF + ;
		"  Renglones malos:   " + cValToChar(nMal) + CRLF + CRLF + ;
		IIf(nMal > 0, "Los malos son los que no traen la barra |.", ""), ;
		"ZCFDICAT - resultado")

Return

// ---------------------------------------------------------------------
// Que hay cargado. Sirve para saber si falta importar algo antes de
// echarle la culpa al visor de que no muestra descripciones.
// ---------------------------------------------------------------------
Static Function CatVer()
	Local cMsg := "CATALOGOS EN LA TABLA" + CRLF + CRLF
	Local cFis := CatFis("ZCT")
	Local nTot := 0

	If !CatHayTb(cFis)
		MsgStop("La tabla " + cFis + " no existe todavia." + CRLF + ;
			"Corre la opcion 1.", "ZCFDICAT")
		Return
	EndIf

	BeginSql Alias "QV"
		SELECT ZCT_CATALO, COUNT(*) AS TOT
		FROM %table:ZCT% ZCT
		WHERE ZCT.%notDel%
		GROUP BY ZCT_CATALO
		ORDER BY ZCT_CATALO
	EndSql

	QV->(DbGoTop())
	While !QV->(Eof())
		cMsg += "  " + PadR(QV->ZCT_CATALO, 24) + StrZero(QV->TOT, 6) + " claves" + CRLF
		nTot += QV->TOT
		QV->(DbSkip())
	EndDo
	QV->(DbCloseArea())

	If nTot == 0
		cMsg += "  (vacia -- corre la opcion 1)" + CRLF
	EndIf

	cMsg += CRLF + "Total: " + cValToChar(nTot) + " claves."

	MsgInfo(cMsg, "ZCFDICAT")

Return

// =====================================================================
// LA FUNCION QUE USA EL RESTO DEL VISOR
//
//   U_ZCATDES("c_FormaPago", "03")  ->  "Transferencia electronica..."
//
// Si no encuentra la clave devuelve la clave misma, no vacio: mas vale
// ver "03" que una columna en blanco que no explica nada.
// =====================================================================
User Function ZCATDES(cCat, cClave)
	Local cRet := ""
	Local nPos := 0
	Local nI   := 0
	Local aCat := {}

	cCat   := AllTrim(cCat)
	cClave := AllTrim(cValToChar(cClave))

	If Empty(cClave)
		Return ""
	EndIf

	// Si la tabla no existe todavia -- porque nadie corrio la opcion 1 --
	// se devuelve la clave tal cual. El visor debe seguir funcionando sin
	// catalogos: mostrar "03" es peor que "Transferencia electronica",
	// pero infinitamente mejor que tronar.
	If Select("ZCT") == 0
		If !ChkFile("ZCT")
			Return cClave
		EndIf
	EndIf

	// c_ClaveProdServ no se cachea: son 52,000 claves y solo se pide en
	// el detalle de un comprobante, nunca en el browse.
	If cCat == "c_ClaveProdServ"
		Return CatSeek(cCat, cClave)
	EndIf

	// Lo demas si: son pocos y el browse los pide miles de veces.
	nPos := AScan(_aCache, {|x| x[1] == cCat })

	If nPos == 0
		aCat := CatMem(cCat)
		aAdd(_aCache, {cCat, aCat})
		nPos := Len(_aCache)
	EndIf

	aCat := _aCache[nPos][2]
	nI   := AScan(aCat, {|x| x[1] == cClave })

	cRet := IIf(nI > 0, aCat[nI][2], cClave)

Return cRet

// ---------------------------------------------------------------------
// Sube un catalogo completo a memoria.
// ---------------------------------------------------------------------
Static Function CatMem(cCat)
	Local aRet := {}

	BeginSql Alias "QM"
		SELECT ZCT_CLAVE, ZCT_DESCRI
		FROM %table:ZCT% ZCT
		WHERE ZCT.%notDel%
		  AND ZCT_FILIAL = %exp:xFilial("ZCT")%
		  AND ZCT_CATALO = %exp:cCat%
	EndSql

	QM->(DbGoTop())
	While !QM->(Eof())
		aAdd(aRet, {AllTrim(QM->ZCT_CLAVE), AllTrim(QM->ZCT_DESCRI)})
		QM->(DbSkip())
	EndDo
	QM->(DbCloseArea())

Return aRet

// ---------------------------------------------------------------------
// Busca una sola clave sin cachear el catalogo entero.
// ---------------------------------------------------------------------
Static Function CatSeek(cCat, cClave)
	Local cRet := cClave

	If Select("ZCT") == 0
		ChkFile("ZCT")
	EndIf
	If Select("ZCT") == 0
		Return cRet
	EndIf

	ZCT->(DbSetOrder(1))
	If ZCT->(MsSeek(xFilial("ZCT") + PadR(cCat, 20) + PadR(cClave, 25)))
		cRet := AllTrim(ZCT->ZCT_DESCRI)
	EndIf

Return cRet
