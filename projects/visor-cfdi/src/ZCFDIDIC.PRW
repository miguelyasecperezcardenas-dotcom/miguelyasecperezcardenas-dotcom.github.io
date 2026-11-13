#INCLUDE "PROTHEUS.CH"
#INCLUDE "TOPCONN.CH"

/*/{Protheus.doc} ZCFDIDIC
Diccionario de datos del visor de CFDI: ZCF, ZCC, ZCI, ZCP, ZCR.

ESTA RUTINA SI ESCRIBE. Es la primera del proyecto que lo hace.

Crea tablas en Oracle y da de alta registros en SX2, SX3 y SIX. Por eso
primero REPORTA lo que va a hacer y no toca nada hasta que se confirme.
Lo que ya existe no se vuelve a crear, asi que se puede correr dos veces
sin duplicar nada.

LAS CINCO TABLAS

  ZCF  Cabecera del CFDI          un renglon por comprobante
  ZCC  Conceptos                  un renglon por partida
  ZCI  Impuestos                  por concepto Y por comprobante
  ZCP  Complemento de pagos       un renglon por documento relacionado
  ZCR  Conciliacion contra Protheus

EL DISENO SALE DE LOS ARCHIVOS, NO DE LA ESPECIFICACION

Se leyeron los XML que hay en el servidor (ZCFDI opcion 2) antes de
definir un solo campo. De ahi:

  - Todos son CFDI 4.0. No hay 3.3, asi que no hay que soportar dos
    versiones ni convertir entre ellas.
  - Tipos I, E, T y P. No hay nomina, asi que el complemento de Nomina
    queda fuera de alcance -- es el mas pesado de parsear y no hay un
    solo archivo que lo necesite.
  - Los impuestos vienen a nivel concepto Y a nivel comprobante. Por eso
    ZCI lleva el campo ZCI_NIVEL en vez de dos tablas separadas.
  - NoIdentificacion trae la clave interna del producto, lo que permite
    ligar el concepto con SB1 (campo ZCC_CODPRO).

SOLO ENTRAN COMPROBANTES TIMBRADOS

La llave de ZCF es la sucursal mas el UUID. Un comprobante sin timbrar
no tiene UUID, asi que varios chocarian en la llave unica.

No es una limitacion tecnica sino una definicion: ZCF guarda el acervo
fiscal, y fiscalmente un comprobante sin timbrar no existe. Los archivos
que se encuentren sin timbre se registran en ZCR con estado 'S', para
que quede constancia de que estaban ahi sin ensuciar el acervo.

Es el mismo criterio del visor de CONTPAQi, que rechaza los documentos
sin nodo de timbre fiscal.

DOS COSAS QUE ANTES SE HACIAN A MANO

  1. Los modos de acceso (Ac. Sucursal / Unidad / Empresa) quedan en
     Compartido desde el codigo. En el Anexo 20 habia que ponerlos a
     mano en cada tabla nueva y se olvidaba.
  2. Los campos numericos se crean como numericos de verdad. En el
     Anexo 20 todo quedo como caracter, y para un visor que despues va a
     calcular IVA eso obligaria a convertir en cada lectura.

@author Claude + Miguel Yasec
@since 09/2026
/*/
User Function ZCFDIDIC()
	Local aTabs := DicDef()

	If !MsgYesNo("Ver que se va a crear?" + CRLF + CRLF + ;
		"Primero se reporta, no se crea nada todavia." + CRLF + ;
		"La creacion se confirma al final.", "ZCFDIDIC")
		Return
	EndIf

	If !MsgYesNo(DicPrev(aTabs) + CRLF + ;
		"CREAR AHORA?", "ZCFDIDIC - confirmar")
		MsgInfo("No se creo nada.", "ZCFDIDIC")
		Return
	EndIf

	Processa({|| DicCrea(aTabs) }, "Creando el diccionario...")

Return

// ---------------------------------------------------------------------
// LA DEFINICION
//
// Cada tabla: {alias, nombre, llave unica, campos}
// Cada campo: {nombre, tipo, tamano, decimales, titulo}
//
// Tipos: C caracter, N numerico, D fecha
// ---------------------------------------------------------------------
Static Function DicDef()
	Local aRet := {}

	// ---------- ZCF: cabecera del comprobante ----------
	aAdd(aRet, {"ZCF", "Visor CFDI - Cabecera", ;
		{"ZCF_FILIAL", "ZCF_UUID"}, {;
		{"ZCF_FILIAL", "C",   2, 0, "Sucursal"          }, ;
		{"ZCF_UUID",   "C",  36, 0, "Folio fiscal", "S"      }, ;
		{"ZCF_VERSIO", "C",   5, 0, "Version CFDI"      }, ;
		{"ZCF_TIPCOM", "C",   1, 0, "Tipo comprobante", "S"  }, ;
		{"ZCF_SERIE",  "C",  25, 0, "Serie", "S"             }, ;
		{"ZCF_FOLIO",  "C",  40, 0, "Folio", "S"             }, ;
		{"ZCF_FECHA",  "D",   8, 0, "Fecha emision", "S"     }, ;
		{"ZCF_HORA",   "C",   8, 0, "Hora emision"      }, ;
		{"ZCF_FORPAG", "C",   2, 0, "Forma de pago"     }, ;
		{"ZCF_METPAG", "C",   3, 0, "Metodo de pago", "S"    }, ;
		{"ZCF_CONDPA", "C", 100, 0, "Condiciones pago"  }, ;
		{"ZCF_MONEDA", "C",   3, 0, "Moneda"            }, ;
		{"ZCF_TIPCAM", "N",  12, 6, "Tipo de cambio"    }, ;
		{"ZCF_SUBTOT", "N",  16, 2, "Subtotal"          }, ;
		{"ZCF_DESCTO", "N",  16, 2, "Descuento"         }, ;
		{"ZCF_TOTAL",  "N",  16, 2, "Total", "S"             }, ;
		{"ZCF_LUGEXP", "C",   5, 0, "Lugar expedicion"  }, ;
		{"ZCF_EXPORT", "C",   2, 0, "Exportacion"       }, ;
		{"ZCF_EMIRFC", "C",  13, 0, "RFC emisor"        }, ;
		{"ZCF_EMINOM", "C", 100, 0, "Nombre emisor"     }, ;
		{"ZCF_EMIREG", "C",   3, 0, "Regimen emisor"    }, ;
		{"ZCF_RECRFC", "C",  13, 0, "RFC receptor", "S"      }, ;
		{"ZCF_RECNOM", "C", 100, 0, "Nombre receptor", "S"   }, ;
		{"ZCF_RECDOM", "C",   5, 0, "CP receptor"       }, ;
		{"ZCF_RECREG", "C",   3, 0, "Regimen receptor"  }, ;
		{"ZCF_RECNRT", "C",  40, 0, "NumRegIdTrib recep"}, ;
		{"ZCF_RECRES", "C",   3, 0, "Residencia fiscal" }, ;
		{"ZCF_USOCFD", "C",   4, 0, "Uso CFDI"          }, ;
		{"ZCF_FECTIM", "D",   8, 0, "Fecha timbrado"    }, ;
		{"ZCF_HORTIM", "C",   8, 0, "Hora timbrado"     }, ;
		{"ZCF_NOCERT", "C",  20, 0, "No certificado"    }, ;
		{"ZCF_CERSAT", "C",  20, 0, "Certificado SAT"   }, ;
		{"ZCF_RFCPAC", "C",  13, 0, "RFC del PAC"       }, ;
		{"ZCF_ESTSAT", "C",   1, 0, "Estatus SAT", "S"       }, ;
		{"ZCF_VALIDE", "C",   1, 0, "Validez"           }, ;
		{"ZCF_MOTIVO", "C", 250, 0, "Motivo de error"   }, ;
		{"ZCF_ORIGEN", "C",   1, 0, "Emitido/Recibido"  }, ;
		{"ZCF_ESPECI", "C",   3, 0, "Especie Protheus"  }, ;
		{"ZCF_ARCHIV", "C", 100, 0, "Archivo origen"    }, ;
		{"ZCF_RUTA",   "C", 100, 0, "Ruta origen"       }, ;
		{"ZCF_FECIMP", "D",   8, 0, "Fecha importacion" }, ;
		{"ZCF_TOTPAG", "N",  16, 2, "Monto total pagos" }, ;
		{"ZCF_BASIVA", "N",  16, 2, "Base IVA 16 pagos" }, ;
		{"ZCF_IVA16",  "N",  16, 2, "IVA 16 de pagos"   }  ;
		}})

	// ---------- ZCC: conceptos ----------
	aAdd(aRet, {"ZCC", "Visor CFDI - Conceptos", ;
		{"ZCC_FILIAL", "ZCC_UUID", "ZCC_ITEM"}, {;
		{"ZCC_FILIAL", "C",   2, 0, "Sucursal"          }, ;
		{"ZCC_UUID",   "C",  36, 0, "Folio fiscal"      }, ;
		{"ZCC_ITEM",   "C",   4, 0, "Item"              }, ;
		{"ZCC_CLAVE",  "C",   8, 0, "Clave prod-serv"   }, ;
		{"ZCC_NOIDEN", "C", 100, 0, "No identificacion" }, ;
		{"ZCC_CANT",   "N",  16, 6, "Cantidad"          }, ;
		{"ZCC_CLAUNI", "C",   3, 0, "Clave unidad"      }, ;
		{"ZCC_UNIDAD", "C",  20, 0, "Unidad"            }, ;
		{"ZCC_DESCRI", "C", 250, 0, "Descripcion"       }, ;
		{"ZCC_VALUNI", "N",  16, 6, "Valor unitario"    }, ;
		{"ZCC_IMPORT", "N",  16, 2, "Importe"           }, ;
		{"ZCC_DESCTO", "N",  16, 2, "Descuento"         }, ;
		{"ZCC_OBJIMP", "C",   2, 0, "Objeto de impuesto"}, ;
		{"ZCC_CODPRO", "C",  15, 0, "Producto ligado"   }  ;
		}})

	// ---------- ZCI: impuestos ----------
	// Una sola tabla para TODOS los niveles. ZCI_NIVEL dice cual:
	//   'C' del concepto
	//   'G' del comprobante completo
	//   'D' del documento relacionado del complemento de pago
	//       (pago20:ImpuestosDR) -- ZCI_ITEM trae el item del ZCP
	//   'P' del pago completo (pago20:ImpuestosP)
	//
	// Los dos ultimos se agregaron sin tabla nueva a proposito: el
	// complemento de pago desglosa su IVA con la misma forma que el
	// resto (impuesto, base, tipo factor, tasa, importe) y es
	// uno-a-muchos igual, asi que meterlo aqui sale gratis y de paso
	// hereda el browse y la exportacion que ya existen. Lo unico que
	// cambia es de QUE cuelga el renglon, y para eso esta ZCI_NIVEL.
	aAdd(aRet, {"ZCI", "Visor CFDI - Impuestos", ;
		{"ZCI_FILIAL", "ZCI_UUID", "ZCI_ITEM", "ZCI_SEQ"}, {;
		{"ZCI_FILIAL", "C",   2, 0, "Sucursal"          }, ;
		{"ZCI_UUID",   "C",  36, 0, "Folio fiscal"      }, ;
		{"ZCI_ITEM",   "C",   4, 0, "Item concepto"     }, ;
		{"ZCI_SEQ",    "C",   3, 0, "Secuencia"         }, ;
		{"ZCI_NIVEL",  "C",   1, 0, "Nivel C/G"         }, ;
		{"ZCI_TIPO",   "C",   1, 0, "Traslado/Retenc"   }, ;
		{"ZCI_IMPUES", "C",   3, 0, "Impuesto"          }, ;
		{"ZCI_BASE",   "N",  16, 2, "Base"              }, ;
		{"ZCI_TIPFAC", "C",  10, 0, "Tipo factor"       }, ;
		{"ZCI_TASA",   "N",  12, 6, "Tasa o cuota"      }, ;
		{"ZCI_IMPORT", "N",  16, 2, "Importe"           }  ;
		}})

	// ---------- ZCP: complemento de pagos ----------
	aAdd(aRet, {"ZCP", "Visor CFDI - Complemento pagos", ;
		{"ZCP_FILIAL", "ZCP_UUID", "ZCP_ITEM"}, {;
		{"ZCP_FILIAL", "C",   2, 0, "Sucursal"          }, ;
		{"ZCP_UUID",   "C",  36, 0, "UUID del REP"      }, ;
		{"ZCP_ITEM",   "C",   4, 0, "Item"              }, ;
		{"ZCP_FECPAG", "D",   8, 0, "Fecha de pago"     }, ;
		{"ZCP_FORPAG", "C",   2, 0, "Forma de pago"     }, ;
		{"ZCP_MONEDA", "C",   3, 0, "Moneda del pago"   }, ;
		{"ZCP_TIPCAM", "N",  12, 6, "Tipo de cambio"    }, ;
		{"ZCP_MONTO",  "N",  16, 2, "Monto del pago"    }, ;
		{"ZCP_UUIDRE", "C",  36, 0, "UUID relacionado"  }, ;
		{"ZCP_SERIE",  "C",  25, 0, "Serie relacionada" }, ;
		{"ZCP_FOLIO",  "C",  40, 0, "Folio relacionado" }, ;
		{"ZCP_PARCIA", "C",   3, 0, "No parcialidad"    }, ;
		{"ZCP_SALANT", "N",  16, 2, "Saldo anterior"    }, ;
		{"ZCP_SALPAG", "N",  16, 2, "Importe pagado"    }, ;
		{"ZCP_SALINS", "N",  16, 2, "Saldo insoluto"    }, ;
		{"ZCP_OBJIMP", "C",   2, 0, "Objeto de impuesto"}, ;
		{"ZCP_IVAPAG", "N",  16, 2, "IVA del pago"      }, ;
		{"ZCP_NUMOPE", "C", 100, 0, "No de operacion"   }, ;
		{"ZCP_MONEDR", "C",   3, 0, "Moneda del docto"  }, ;
		{"ZCP_EQUIVA", "N",  18, 6, "Equivalencia DR"   }  ;
		}})

	// ---------- ZCR: conciliacion ----------
	// Aqui vive la respuesta a "que hay en la base que no tiene XML" y
	// viceversa. Estados:
	//   'C' conciliado   XML y documento de Protheus se encontraron
	//   'X' solo XML     hay comprobante pero no documento en la base
	//   'D' solo doc     hay documento en la base pero no llego su XML
	//   'S' sin timbre   habia archivo pero no estaba timbrado
	aAdd(aRet, {"ZCR", "Visor CFDI - Conciliacion", ;
		{"ZCR_FILIAL", "ZCR_UUID", "ZCR_TABLA", "ZCR_SERIE", "ZCR_DOC"}, {;
		{"ZCR_FILIAL", "C",   2, 0, "Sucursal"          }, ;
		{"ZCR_UUID",   "C",  36, 0, "Folio fiscal"      }, ;
		{"ZCR_TABLA",  "C",   3, 0, "Tabla Protheus"    }, ;
		{"ZCR_SERIE",  "C",   3, 0, "Serie documento"   }, ;
		{"ZCR_DOC",    "C",   9, 0, "Numero documento"  }, ;
		{"ZCR_ESTADO", "C",   1, 0, "Estado C/X/D/S"    }, ;
		{"ZCR_FECHA",  "D",   8, 0, "Fecha del cruce"   }, ;
		{"ZCR_OBS",    "C", 250, 0, "Observacion"       }  ;
		}})

	// ---------- ZCE: comercio exterior, cabecera ----------
	// Un renglon por comprobante. Son 23 datos que solo traen los
	// comprobantes de exportacion -- 9 de 66 en homologacion --, asi
	// que meterlos en ZCF dejaria 57 renglones con 23 columnas vacias.
	// Aqui tambien viven los dos domicilios (emisor y receptor), que en
	// el XML son nodos distintos pero son 1 a 1 con el comprobante y no
	// ganan nada estando aparte.
	aAdd(aRet, {"ZCE", "Visor CFDI - Comercio exterior", ;
		{"ZCE_FILIAL", "ZCE_UUID"}, {;
		{"ZCE_FILIAL", "C",   2, 0, "Sucursal"          }, ;
		{"ZCE_UUID",   "C",  36, 0, "Folio fiscal"      }, ;
		{"ZCE_VERSIO", "C",   5, 0, "Version CCE"       }, ;
		{"ZCE_CVEPED", "C",  16, 0, "Clave de pedimento"}, ;
		{"ZCE_CERORI", "C",   1, 0, "Certificado origen"}, ;
		{"ZCE_NUMEXP", "C",  50, 0, "Exportador confiab"}, ;
		{"ZCE_INCOTE", "C",   7, 0, "Incoterm"          }, ;
		{"ZCE_MOTTRA", "C",   2, 0, "Motivo traslado"   }, ;
		{"ZCE_TIPCAM", "N",  14, 6, "Tipo cambio USD"   }, ;
		{"ZCE_TOTUSD", "N",  16, 2, "Total en dolares"  }, ;
		{"ZCE_EMICAL", "C", 100, 0, "Emisor calle"      }, ;
		{"ZCE_EMICP",  "C",  10, 0, "Emisor CP"         }, ;
		{"ZCE_EMICOL", "C",  60, 0, "Emisor colonia"    }, ;
		{"ZCE_EMIMUN", "C",  60, 0, "Emisor municipio"  }, ;
		{"ZCE_EMIEST", "C",  10, 0, "Emisor estado"     }, ;
		{"ZCE_EMIPAI", "C",   3, 0, "Emisor pais"       }, ;
		{"ZCE_RECNRT", "C",  40, 0, "Receptor reg trib" }, ;
		{"ZCE_RECCAL", "C", 100, 0, "Receptor calle"    }, ;
		{"ZCE_RECCP",  "C",  10, 0, "Receptor CP"       }, ;
		{"ZCE_RECCOL", "C",  60, 0, "Receptor colonia"  }, ;
		{"ZCE_RECMUN", "C",  60, 0, "Receptor municipio"}, ;
		{"ZCE_RECEST", "C",  10, 0, "Receptor estado"   }, ;
		{"ZCE_RECPAI", "C",   3, 0, "Receptor pais"     }  ;
		}})

	// ---------- ZCM: mercancias de comercio exterior ----------
	// Uno a muchos por comprobante. La fraccion arancelaria y el valor
	// en dolares son lo primero que pide una revision de exportacion.
	aAdd(aRet, {"ZCM", "Visor CFDI - Mercancias CE", ;
		{"ZCM_FILIAL", "ZCM_UUID", "ZCM_ITEM"}, {;
		{"ZCM_FILIAL", "C",   2, 0, "Sucursal"          }, ;
		{"ZCM_UUID",   "C",  36, 0, "Folio fiscal"      }, ;
		{"ZCM_ITEM",   "C",   4, 0, "Item"              }, ;
		{"ZCM_NOIDEN", "C", 100, 0, "No identificacion" }, ;
		{"ZCM_FRACC",  "C",  10, 0, "Fraccion arancel"  }, ;
		{"ZCM_CANADU", "N",  16, 3, "Cantidad aduana"   }, ;
		{"ZCM_UNIADU", "C",   3, 0, "Unidad aduana"     }, ;
		{"ZCM_VALUNI", "N",  16, 6, "Valor unit aduana" }, ;
		{"ZCM_VALDOL", "N",  16, 2, "Valor en dolares"  }  ;
		}})

	// ---------- ZCA: informacion aduanera del concepto ----------
	// Tabla propia y no un campo en ZCC porque el pedimento cuelga del
	// CONCEPTO y puede venir mas de uno por concepto. Guardar solo el
	// primero seria un hueco silencioso de los que ya costaron tiempo
	// en este proyecto.
	aAdd(aRet, {"ZCA", "Visor CFDI - Informacion aduanera", ;
		{"ZCA_FILIAL", "ZCA_UUID", "ZCA_ITEM", "ZCA_SEQ"}, {;
		{"ZCA_FILIAL", "C",   2, 0, "Sucursal"          }, ;
		{"ZCA_UUID",   "C",  36, 0, "Folio fiscal"      }, ;
		{"ZCA_ITEM",   "C",   4, 0, "Item concepto"     }, ;
		{"ZCA_SEQ",    "C",   3, 0, "Secuencia"         }, ;
		{"ZCA_PEDIME", "C",  21, 0, "Numero pedimento"  }  ;
		}})

	// ---------- ZCL: CFDI relacionados ----------
	// Uno a muchos, y por partida doble: el nodo CfdiRelacionados puede
	// repetirse -- uno por TipoRelacion -- y cada uno trae varios
	// CfdiRelacionado. Por eso el tipo va en CADA renglon y no en una
	// cabecera: un mismo comprobante puede sustituir a uno y ser nota
	// de credito de otro.
	//
	// En homologacion puede haber pocos archivos con este nodo, pero eso no
	// mide su importancia: en produccion pueden ser muchos. Es el unico dato que dice que NC
	// cancela que factura.
	aAdd(aRet, {"ZCL", "Visor CFDI - CFDI relacionados", ;
		{"ZCL_FILIAL", "ZCL_UUID", "ZCL_ITEM"}, {;
		{"ZCL_FILIAL", "C",   2, 0, "Sucursal"          }, ;
		{"ZCL_UUID",   "C",  36, 0, "Folio fiscal"      }, ;
		{"ZCL_ITEM",   "C",   4, 0, "Item"              }, ;
		{"ZCL_TIPREL", "C",   2, 0, "Tipo de relacion"  }, ;
		{"ZCL_UUIDRE", "C",  36, 0, "UUID relacionado"  }  ;
		}})

	// ---------- ZCT: carta porte, cabecera ----------
	// Un renglon por comprobante. Aqui viven los datos del viaje que
	// son uno solo -- IdCCP, distancia, transporte internacional -- y
	// TODO el autotransporte, que en el XML son tres nodos anidados
	// (Autotransporte, IdentificacionVehicular, Seguros) pero los tres
	// son 1 a 1 con la carta porte: un viaje, un vehiculo, una poliza.
	// Separarlos en tablas solo obligaria a tres joins para contestar
	// "que camion llevo esto".
	aAdd(aRet, {"ZCT", "Visor CFDI - Carta porte", ;
		{"ZCT_FILIAL", "ZCT_UUID"}, {;
		{"ZCT_FILIAL", "C",   2, 0, "Sucursal"          }, ;
		{"ZCT_UUID",   "C",  36, 0, "Folio fiscal"      }, ;
		{"ZCT_VERSIO", "C",   5, 0, "Version carta porte"}, ;
		{"ZCT_IDCCP",  "C",  36, 0, "IdCCP"             }, ;
		{"ZCT_TRAINT", "C",   3, 0, "Transp internac"   }, ;
		{"ZCT_TOTDIS", "N",  16, 2, "Distancia total"   }, ;
		{"ZCT_NUMMER", "N",   6, 0, "Total mercancias"  }, ;
		{"ZCT_PESBRU", "N",  16, 3, "Peso bruto total"  }, ;
		{"ZCT_UNIPES", "C",   3, 0, "Unidad de peso"    }, ;
		{"ZCT_PERSCT", "C",   6, 0, "Tipo permiso SCT"  }, ;
		{"ZCT_NUMPER", "C",  50, 0, "Num permiso SCT"   }, ;
		{"ZCT_PLACA",  "C",  10, 0, "Placa del vehiculo"}, ;
		{"ZCT_ANIOVM", "N",   4, 0, "Anio del modelo"   }, ;
		{"ZCT_CONFVE", "C",   6, 0, "Config vehicular"  }, ;
		{"ZCT_ASEGUR", "C",  50, 0, "Aseguradora"       }, ;
		{"ZCT_POLIZA", "C",  30, 0, "Poliza resp civil" }  ;
		}})

	// ---------- ZCU: ubicaciones de la carta porte ----------
	// Uno a muchos. El Domicilio va aplanado aqui y no en tabla aparte
	// porque es 1 a 1 con la ubicacion: una parada, una direccion.
	aAdd(aRet, {"ZCU", "Visor CFDI - CP Ubicaciones", ;
		{"ZCU_FILIAL", "ZCU_UUID", "ZCU_ITEM"}, {;
		{"ZCU_FILIAL", "C",   2, 0, "Sucursal"          }, ;
		{"ZCU_UUID",   "C",  36, 0, "Folio fiscal"      }, ;
		{"ZCU_ITEM",   "C",   4, 0, "Item"              }, ;
		{"ZCU_TIPO",   "C",  12, 0, "Origen o destino"  }, ;
		{"ZCU_RFC",    "C",  13, 0, "RFC remit-destin"  }, ;
		{"ZCU_NOMBRE", "C", 100, 0, "Nombre remit-dest" }, ;
		{"ZCU_FECHA",  "D",   8, 0, "Fecha sal-llegada" }, ;
		{"ZCU_HORA",   "C",   8, 0, "Hora sal-llegada"  }, ;
		{"ZCU_DISTAN", "N",  16, 2, "Distancia recorrida"}, ;
		{"ZCU_CALLE",  "C", 100, 0, "Calle"             }, ;
		{"ZCU_NUMEXT", "C",  20, 0, "Numero exterior"   }, ;
		{"ZCU_CP",     "C",  10, 0, "Codigo postal"     }, ;
		{"ZCU_LOCALI", "C",   6, 0, "Localidad"         }, ;
		{"ZCU_MUNICI", "C",   6, 0, "Municipio"         }, ;
		{"ZCU_ESTADO", "C",  10, 0, "Estado"            }, ;
		{"ZCU_PAIS",   "C",   3, 0, "Pais"              }  ;
		}})

	// ---------- ZCB: bienes transportados ----------
	// Uno a muchos. NO se reusa ZCM, aunque el nodo del XML tambien se
	// llame Mercancia: no comparten un solo campo. Las de comercio
	// exterior traen fraccion arancelaria y valor en dolares; estas
	// traen clave de bien transportado y peso en kilos. Juntar dos
	// complementos por el nombre del nodo es el mismo error que casi
	// deja marcadas como leidas las rutas de carta porte en el censo.
	aAdd(aRet, {"ZCB", "Visor CFDI - CP Bienes transportados", ;
		{"ZCB_FILIAL", "ZCB_UUID", "ZCB_ITEM"}, {;
		{"ZCB_FILIAL", "C",   2, 0, "Sucursal"          }, ;
		{"ZCB_UUID",   "C",  36, 0, "Folio fiscal"      }, ;
		{"ZCB_ITEM",   "C",   4, 0, "Item"              }, ;
		{"ZCB_BIENES", "C",   8, 0, "Bienes transp"     }, ;
		{"ZCB_DESCRI", "C", 250, 0, "Descripcion"       }, ;
		{"ZCB_CANT",   "N",  16, 6, "Cantidad"          }, ;
		{"ZCB_CLAUNI", "C",   3, 0, "Clave unidad"      }, ;
		{"ZCB_PESKG",  "N",  16, 3, "Peso en Kg"        }, ;
		{"ZCB_VALOR",  "N",  16, 2, "Valor mercancia"   }, ;
		{"ZCB_MONEDA", "C",   3, 0, "Moneda"            }  ;
		}})

	// ---------- ZCG: figuras de transporte ----------
	// Uno a muchos: el operador, y en su caso el propietario o el
	// arrendatario del vehiculo. El numero de licencia es lo que pide
	// una revision de transporte.
	aAdd(aRet, {"ZCG", "Visor CFDI - CP Figuras transporte", ;
		{"ZCG_FILIAL", "ZCG_UUID", "ZCG_ITEM"}, {;
		{"ZCG_FILIAL", "C",   2, 0, "Sucursal"          }, ;
		{"ZCG_UUID",   "C",  36, 0, "Folio fiscal"      }, ;
		{"ZCG_ITEM",   "C",   4, 0, "Item"              }, ;
		{"ZCG_TIPFIG", "C",   2, 0, "Tipo de figura"    }, ;
		{"ZCG_RFC",    "C",  13, 0, "RFC de la figura"  }, ;
		{"ZCG_NOMBRE", "C", 100, 0, "Nombre"            }, ;
		{"ZCG_LICENC", "C",  20, 0, "Num de licencia"   }  ;
		}})

Return aRet

// ---------------------------------------------------------------------
// El reporte previo. No toca nada: solo dice que existe y que falta.
// ---------------------------------------------------------------------
Static Function DicPrev(aTabs)
	Local cRet := "SE VAN A CREAR ESTAS TABLAS:" + CRLF + CRLF
	Local nI   := 0
	Local cAli := ""

	For nI := 1 To Len(aTabs)
		cAli := aTabs[nI][1]
		cRet += "  " + cAli + "  " + PadR(aTabs[nI][2], 32) + ;
			cValToChar(Len(aTabs[nI][4])) + " campos"

		If DicHayTb(DicFis(cAli))
			cRet += "   [ya existe]"
		EndIf
		cRet += CRLF
	Next nI

	cRet += CRLF + "Lo que ya exista NO se vuelve a crear." + CRLF
	cRet += "Solo se agrega lo que falte." + CRLF + CRLF

Return cRet

// ---------------------------------------------------------------------
Static Function DicCrea(aTabs)
	Local cMsg := ""
	Local nI   := 0

	For nI := 1 To Len(aTabs)
		cMsg += DicUna(aTabs[nI]) + CRLF
	Next nI

	MsgInfo(cMsg, "ZCFDIDIC - resultado")

Return

// ---------------------------------------------------------------------
// Crea una tabla completa: fisica en Oracle, SX2, SX3 y SIX.
// ---------------------------------------------------------------------
Static Function DicUna(aTab)
	Local cAli  := aTab[1]
	Local cNom  := aTab[2]
	Local aLlav := aTab[3]
	Local aCpo  := aTab[4]
	Local cFis  := DicFis(cAli)
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

	// ---------- A) tabla fisica ----------
	If DicHayTb(cFis)
		cMsg += "  tabla fisica ya existia" + CRLF

		// Ya existe, pero puede faltarle columnas: el diccionario crece
		// cada vez que se aprende a leer un nodo nuevo del XML.
		cMsg += DicAlta(cFis, aCpo)
	Else
		cSql := "CREATE TABLE " + cFis + " ("
		For nI := 1 To Len(aCpo)
			If nI > 1
				cSql += ", "
			EndIf
			cSql += aCpo[nI][1] + " " + DicTipo(aCpo[nI])
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
		cMsg += "  indice de orden 1: " + IIf(nRet < 0, "ERROR " + TCSQLError(), "OK") + CRLF

		nRet := TCSQLExec("CREATE UNIQUE INDEX " + cFis + "_PK ON " + cFis + " (R_E_C_N_O_)")
		cMsg += "  indice _PK: " + IIf(nRet < 0, "ERROR", "OK") + CRLF

		nRet := TCSQLExec("CREATE UNIQUE INDEX " + cFis + "_UNQ ON " + cFis + ;
			" (" + cCols + ", R_E_C_D_E_L_)")
		cMsg += "  indice _UNQ: " + IIf(nRet < 0, "ERROR", "OK") + CRLF
	EndIf

	// ---------- B) SX2 ----------
	cMsg += DicSX2(cAli, cFis, cNom, cChav)

	// ---------- C) SX3 ----------
	cMsg += DicSX3(cAli, aCpo)

	// ---------- D) SIX ----------
	cMsg += DicSIX(cAli, cChav)

	// ---------- E) columnas del browse ----------
	// Se hace siempre, tambien cuando la tabla ya existia: asi se puede
	// cambiar que columnas se ven sin rehacer nada.
	cMsg += DicBrw(cAli, aCpo)

	// ---------- F) orden de los campos en SX3 ----------
	cMsg += DicOrden(cAli, aCpo)

	// ---------- G) que ve la SESION ABIERTA ----------
	cMsg += DicSesion(cAli, aCpo)

Return cMsg

// ---------------------------------------------------------------------
// RENUMERAR X3_ORDEM PARA QUE NO HAYA REPETIDOS
//
// Este era el error de verdad, y estuvo escondido mucho tiempo detras
// de "hay que reiniciar Protheus".
//
// DicSX3 le pone a cada campo nuevo X3_ORDEM = su POSICION EN EL
// ARREGLO. Eso esta bien la primera vez, cuando se dan de alta los 39
// campos de corrido. Pero al meter dos campos nuevos EN MEDIO del
// arreglo (ZCF_RECNRT y ZCF_RECRES quedaron en 26 y 27), los campos que
// ya estaban en SX3 conservan el orden con el que nacieron: ZCF_USOCFD
// seguia siendo 26, ZCF_FECTIM 27, y asi. El alta no los toca porque
// DicHayCp dice que ya existen.
//
// Resultado: dos campos distintos con el mismo X3_ORDEM. Protheus arma
// la lista de campos de la tabla ordenando por X3_ORDEM, y con un orden
// repetido uno de los dos se pierde -- justo los dos que "la sesion no
// veia". Por eso reiniciar no servia de nada: no era cache, era el
// diccionario mal numerado.
//
// Se renumera SIEMPRE, por SQL y segun la posicion en el arreglo, de
// modo que la rutina se arregla sola cada vez que corre y el problema
// no puede volver aunque se metan campos en medio otra vez.
// ---------------------------------------------------------------------
Static Function DicOrden(cAli, aCpo)
	Local nI   := 0
	Local nCam := 0
	Local cFis := DicFis("SX3")
	Local cSql := ""
	Local aAct := {}
	Local nPos := 0
	Local cDeb := ""

	// como estan hoy
	cSql := "SELECT TRIM(X3_CAMPO) AS CPO, TRIM(X3_ORDEM) AS ORD FROM " + cFis + ;
		" WHERE D_E_L_E_T_ = ' ' AND TRIM(X3_ARQUIVO) = '" + AllTrim(cAli) + "'"

	TCQuery cSql New Alias "QN"
	QN->(DbGoTop())
	While !QN->(Eof())
		aAdd(aAct, {AllTrim(cValToChar(QN->CPO)), AllTrim(cValToChar(QN->ORD))})
		QN->(DbSkip())
	EndDo
	QN->(DbCloseArea())

	For nI := 1 To Len(aCpo)
		nPos := aScan(aAct, {|x| x[1] == AllTrim(aCpo[nI][1]) })
		If nPos == 0
			Loop
		EndIf
		If aAct[nPos][2] == StrZero(nI, 2)
			Loop
		EndIf
		cSql := "UPDATE " + cFis + " SET X3_ORDEM = '" + StrZero(nI, 2) + "'" + ;
			" WHERE D_E_L_E_T_ = ' '" + ;
			" AND TRIM(X3_ARQUIVO) = '" + AllTrim(cAli) + "'" + ;
			" AND TRIM(X3_CAMPO) = '" + AllTrim(aCpo[nI][1]) + "'"
		If TCSQLExec(cSql) == 0
			nCam++
			cDeb += "     " + aCpo[nI][1] + ": " + aAct[nPos][2] + ;
				" -> " + StrZero(nI, 2) + CRLF
		EndIf
	Next nI

	If nCam == 0
		Return "  orden SX3: ya estaba bien" + CRLF
	EndIf

	Return "  orden SX3: " + cValToChar(nCam) + " campo(s) renumerado(s)" + CRLF + ;
		cDeb + ;
		"     Habia ordenes repetidos y por eso la sesion perdia campos." + CRLF + ;
		"     AHORA SI: sal de Protheus y vuelve a entrar." + CRLF

// ---------------------------------------------------------------------
// QUE CAMPOS VE LA SESION ABIERTA
//
// Las tres comprobaciones de arriba preguntan a la BASE: DicAlta mira
// USER_TAB_COLUMNS y DicSX3 consulta SX3 por SQL. Las dos pueden decir
// "todo en orden" mientras la sesion sigue sin ver el campo, porque
// Protheus lee el diccionario AL ABRIR LA SESION y el alias se quedo
// con la foto vieja.
//
// Eso ya costo una tarde: el campo estaba en Oracle y en SX3, el import
// lo escribia al vacio, y el unico aviso de reiniciar salia nada mas en
// la corrida que agregaba el campo -- justo la que uno ya paso cuando
// vuelve a revisar porque algo no cuadra.
//
// Por eso esta comprobacion es contra el ALIAS, no contra la base, y se
// hace SIEMPRE.
// ---------------------------------------------------------------------
Static Function DicSesion(cAli, aCpo)
	Local nI    := 0
	Local cFal  := ""
	Local nFal  := 0
	Local cTes  := ""

	If Select(cAli) == 0
		ChkFile(cAli)
	EndIf

	If Select(cAli) == 0
		Return "  sesion: no se pudo abrir " + cAli + " para comprobar" + CRLF
	EndIf

	// Un campo que la sesion SI ve, del mismo molde, para comparar
	// contra el: lo que este mal en el invisible salta como diferencia.
	For nI := 1 To Len(aCpo)
		If (cAli)->(FieldPos(aCpo[nI][1])) > 0
			cTes := aCpo[nI][1]
			Exit
		EndIf
	Next nI

	For nI := 1 To Len(aCpo)
		If (cAli)->(FieldPos(aCpo[nI][1])) == 0
			nFal++
			cFal += "     " + aCpo[nI][1] + CRLF
			cFal += DicPeri(cAli, aCpo[nI][1], cTes, aCpo[nI][2])
		EndIf
	Next nI

	If nFal == 0
		Return "  sesion: ve los " + cValToChar(Len(aCpo)) + " campos" + CRLF
	EndIf

	Return "  [!!] LA SESION NO VE " + cValToChar(nFal) + " CAMPO(S):" + CRLF + ;
		cFal + ;
		"     Reiniciar SmartClient no siempre alcanza: el AppServer" + CRLF + ;
		"     tambien cachea el diccionario. Si ya reiniciaste y el" + CRLF + ;
		"     aviso sigue, hay que reiniciar el SERVICIO DEL APPSERVER." + CRLF + ;
		"     Mientras tanto el import escribe estos campos por SQL" + CRLF + ;
		"     directo, asi que el dato no se pierde." + CRLF

// ---------------------------------------------------------------------
// PERITAJE DE UN CAMPO QUE LA SESION NO VE
//
// Si la sesion no ve el campo hay tres sospechosos y conviene separarlos
// antes de mandar a nadie a reiniciar nada:
//   - el renglon de SX3 esta borrado logicamente (D_E_L_E_T_ = '*')
//   - el renglon de SX3 trae un X3_ORDEM que choca con otro campo
//   - todo esta bien y lo unico que pasa es que el diccionario en
//     memoria es viejo
// De paso se cuenta cuantos renglones de la tabla ya traen dato en esa
// columna: si hay, el import si la escribio aunque el alias no la vea,
// y no hace falta reimportar despues de reiniciar.
//
// OJO con el conteo: en Oracle la cadena vacia ES NULL, asi que un
// "AND TRIM(campo) <> ''" se vuelve una comparacion contra NULL, nunca
// da verdadero y tira TODAS las filas. El contador daba 0 aunque el
// dato estuviera escrito. Con TRIM(campo) IS NOT NULL basta: un campo
// lleno de espacios, al pasar por TRIM, ya queda NULL.
// ---------------------------------------------------------------------
Static Function DicPeri(cAli, cCampo, cTes, cTipo)
	Local cRet := ""
	Local cSql := ""
	Local nCon := 0
	Local cOrd := ""
	Local cDel := ""

	Default cTes  := ""
	Default cTipo := "C"

	// 1. como esta el renglon en SX3
	cSql := "SELECT TRIM(X3_ORDEM) AS ORD, D_E_L_E_T_ AS DEL FROM " + ;
		DicFis("SX3") + " WHERE TRIM(X3_ARQUIVO) = '" + AllTrim(cAli) + ;
		"' AND TRIM(X3_CAMPO) = '" + AllTrim(cCampo) + "'"

	TCQuery cSql New Alias "QP"
	QP->(DbGoTop())
	If QP->(Eof())
		cRet += "        SX3: NO HAY RENGLON (el campo no esta en el" + CRLF
		cRet += "             diccionario; no es cache, es alta faltante)" + CRLF
	Else
		cOrd := AllTrim(cValToChar(QP->ORD))
		cDel := cValToChar(QP->DEL)
		If AllTrim(cDel) == "*"
			cRet += "        SX3: RENGLON BORRADO (D_E_L_E_T_ = '*')." + CRLF
			cRet += "             Reiniciar no lo va a arreglar." + CRLF
		Else
			cRet += "        SX3: ok, orden " + cOrd + CRLF
		EndIf
	EndIf
	QP->(DbCloseArea())

	// 2. cuantos renglones de la tabla ya traen dato
	// En un campo NUMERICO, "IS NOT NULL" no dice nada: el ALTER TABLE
	// deja CERO en todos los renglones que ya existian, asi que una
	// columna recien creada reporta la tabla entera y parece llena.
	// Enganya igual que el contador que daba 0 de mas, pero hacia el
	// lado optimista, que es peor. Para numericos se cuenta lo que es
	// distinto de cero.
	If cTipo == "N"
		cSql := "SELECT COUNT(*) AS TOT FROM " + DicFis(cAli) + ;
			" WHERE D_E_L_E_T_ = ' ' AND " + AllTrim(cCampo) + " <> 0"
	Else
		cSql := "SELECT COUNT(*) AS TOT FROM " + DicFis(cAli) + ;
			" WHERE D_E_L_E_T_ = ' ' AND TRIM(" + AllTrim(cCampo) + ") IS NOT NULL"
	EndIf

	TCQuery cSql New Alias "QD"
	QD->(DbGoTop())
	nCon := QD->TOT
	QD->(DbCloseArea())

	cRet += "        datos en la base: " + cValToChar(nCon) + " renglon(es)" + ;
		IIf(cTipo == "N", " con valor <> 0", "") + CRLF
	If nCon > 0
		cRet += "             (ya se escribio; solo falta que la sesion" + CRLF
		cRet += "              lo vea para mostrarlo)" + CRLF
	EndIf

	// 3. en que se diferencia del renglon de un campo que SI se ve
	cRet += DicComp(cAli, cCampo, cTes)

Return cRet

// ---------------------------------------------------------------------
// COMPARAR EL RENGLON DE SX3 DE DOS CAMPOS DE LA MISMA TABLA
//
// Cuando el campo esta dado de alta, no esta borrado y el orden ya no
// choca, y aun asi la sesion no lo ve, lo que queda es que alguna
// columna del renglon de SX3 salio distinta: X3_USADO, X3_CONTEXT (un
// campo virtual no vive en la tabla fisica), X3_PROPRI, X3_RESERV...
// Adivinar cual es perder la tarde. Como los dos renglones salieron del
// MISMO molde, basta compararlos columna por columna contra un campo
// que la sesion si ve: lo que este mal aparece como diferencia y lo
// demas se calla.
// ---------------------------------------------------------------------
Static Function DicComp(cAli, cCampo, cTes)
	Local cRet := ""
	Local cSql := ""
	Local aMal := {}
	Local aBue := {}
	Local aUno := {}
	Local nI   := 0
	Local nDif := 0
	Local cNom := ""

	If Empty(cTes)
		Return "        (no hay campo testigo para comparar)" + CRLF
	EndIf

	cSql := "SELECT * FROM " + DicFis("SX3") + ;
		" WHERE TRIM(X3_ARQUIVO) = '" + AllTrim(cAli) + "'" + ;
		" AND TRIM(X3_CAMPO) IN ('" + AllTrim(cCampo) + "','" + AllTrim(cTes) + "')" + ;
		" ORDER BY X3_CAMPO"

	TCQuery cSql New Alias "QX"
	QX->(DbGoTop())
	While !QX->(Eof())
		aUno := {}
		For nI := 1 To QX->(FCount())
			aAdd(aUno, {QX->(FieldName(nI)), AllTrim(cValToChar(QX->(FieldGet(nI))))})
		Next nI
		If AllTrim(cValToChar(QX->X3_CAMPO)) == AllTrim(cCampo)
			aMal := aUno
		Else
			aBue := aUno
		EndIf
		QX->(DbSkip())
	EndDo
	QX->(DbCloseArea())

	If Len(aMal) == 0 .Or. Len(aBue) == 0
		Return "        (no se pudo comparar contra " + AllTrim(cTes) + ")" + CRLF
	EndIf

	cRet += "        vs " + AllTrim(cTes) + " (que si se ve):" + CRLF

	For nI := 1 To Len(aMal)
		cNom := AllTrim(aMal[nI][1])
		// estas tienen que ser distintas por definicion
		If cNom $ "X3_CAMPO/X3_ORDEM/X3_TITULO/X3_TITSPA/X3_TITENG/" + ;
			"X3_DESCRIC/X3_DESCSPA/X3_DESCENG/X3_TAMANHO/X3_TIPO/" + ;
			"X3_DECIMAL/X3_PICTURE/R_E_C_N_O_/R_E_C_D_E_L_/X3_BROWSE"
			Loop
		EndIf
		If aMal[nI][2] == aBue[nI][2]
			Loop
		EndIf
		nDif++
		cRet += "           " + cNom + ": [" + aMal[nI][2] + "]" + ;
			" vs [" + aBue[nI][2] + "]" + CRLF
	Next nI

	If nDif == 0
		cRet += "           sin diferencias -- el renglon esta bien y lo" + CRLF
		cRet += "           que falla es el diccionario en memoria." + CRLF
	EndIf

Return cRet

// ---------------------------------------------------------------------
// AGREGAR A LA TABLA FISICA LAS COLUMNAS QUE LE FALTEN
//
// Esto faltaba, y era un hueco serio. DicSX3 si agrega a SX3 los campos
// nuevos, pero la tabla de Oracle solo se creaba completa la primera
// vez. Agregar un campo al arreglo del diccionario dejaba a Protheus
// viendo en SX3 una columna que en la base no existe -- y eso no falla
// al crear: falla despues, al leer, con un error que no apunta aqui.
//
// Se pregunta a la base que columnas tiene de verdad, en vez de
// confiar en el alias: el alias refleja el diccionario de cuando se
// abrio la sesion, que es justo lo que no sirve para esto.
//
// Las columnas se agregan de una en una a proposito. Un ALTER TABLE con
// varias se cae entero si una sola falla, y no dice cual.
// ---------------------------------------------------------------------
Static Function DicAlta(cFis, aCpo)
	Local cRet := ""
	Local aHay := {}
	Local nI   := 0
	Local nRet := 0
	Local nNue := 0
	Local cSql := ""

	aHay := DicColumnas(cFis)

	If Len(aHay) == 0
		Return "  [!!] no se pudo leer las columnas de " + cFis + CRLF
	EndIf

	For nI := 1 To Len(aCpo)

		If aScan(aHay, {|x| x == Upper(AllTrim(aCpo[nI][1])) }) > 0
			Loop
		EndIf

		cSql := "ALTER TABLE " + cFis + " ADD " + ;
			aCpo[nI][1] + " " + DicTipo(aCpo[nI])

		nRet := TCSQLExec(cSql)

		cRet += "  + " + PadR(aCpo[nI][1], 12) + ;
			IIf(nRet < 0, "ERROR " + TCSQLError(), "agregada") + CRLF

		If nRet >= 0
			nNue++
		EndIf

	Next nI

	If nNue == 0 .And. Empty(cRet)
		Return "  no le falta ninguna columna" + CRLF
	EndIf

	If nNue > 0
		cRet += "  (" + cValToChar(nNue) + " columna(s) nueva(s) -- hay que" + CRLF
		cRet += "   SALIR Y VOLVER A ENTRAR para poder usarlas)" + CRLF
	EndIf

Return cRet

// ---------------------------------------------------------------------
// Las columnas que la tabla tiene en la base, en mayusculas.
// ---------------------------------------------------------------------
Static Function DicColumnas(cFis)
	Local aRet := {}
	Local cSql := ""

	cSql := "SELECT COLUMN_NAME FROM USER_TAB_COLUMNS "
	cSql += "WHERE TABLE_NAME = '" + Upper(AllTrim(cFis)) + "'"

	TCQuery cSql New Alias "QDC"

	QDC->(DbGoTop())
	Do While !QDC->(Eof())
		aAdd(aRet, Upper(AllTrim(QDC->COLUMN_NAME)))
		QDC->(DbSkip())
	EndDo

	QDC->(DbCloseArea())

Return aRet

// ---------------------------------------------------------------------
// Tipo de columna en Oracle.
//
// Protheus guarda las fechas como texto AAAAMMDD, no como DATE. Los
// numericos SI se crean numericos: el visor va a calcular IVA sobre
// ellos y convertir texto en cada lectura seria absurdo.
// ---------------------------------------------------------------------
Static Function DicTipo(aCpo)
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
// Nombre fisico: alias + sufijo del grupo de empresas.
// ---------------------------------------------------------------------
Static Function DicFis(cAli)
Return AllTrim(cAli) + SubStr(AllTrim(RetSqlName("SF2")), 4)

// ---------------------------------------------------------------------
// Pone X3_BROWSE en los campos ya dados de alta, segun la definicion.
// ---------------------------------------------------------------------
Static Function DicBrw(cAli, aCpo)
	Local nN   := 0
	Local nV   := 0
	Local nP   := 0
	Local cQ   := ""
	Local cCpo := ""
	Local cDmp := ""

	If Select("SX3") == 0
		ChkFile("SX3")
	EndIf
	If Select("SX3") == 0
		Return "  [!!] no se pudo abrir SX3 para marcar columnas" + CRLF
	EndIf

	// Recorremos SX3 por alias, sin depender del indice por campo.
	SX3->(DbSetOrder(1))
	SX3->(DbGoTop())
	If !SX3->(MsSeek(PadR(cAli, 2)))
		// si el seek no pega, barremos todo el archivo
		SX3->(DbGoTop())
	EndIf

	Do While !SX3->(Eof())

		If AllTrim(SX3->X3_ARQUIVO) != AllTrim(cAli)
			SX3->(DbSkip())
			Loop
		EndIf

		cCpo := AllTrim(SX3->X3_CAMPO)
		nP   := AScan(aCpo, {|x| AllTrim(x[1]) == cCpo })

		If nP > 0
			nV++
			cQ := DicVis(aCpo[nP])
			If AllTrim(SX3->X3_BROWSE) != cQ
				RecLock("SX3", .F.)
				SX3->X3_BROWSE := cQ
				SX3->(MsUnlock())
				nN++
			EndIf

			// Diagnostico: solo de los campos que queremos ver en el browse
			If cQ == "S"
				cDmp += "    " + PadR(cCpo, 12)
				cDmp += " BROWSE=[" + AllTrim(SX3->X3_BROWSE) + "]"
				cDmp += " NIVEL=" + cValToChar(SX3->X3_NIVEL)
				cDmp += " USADO=[" + AllTrim(SX3->X3_USADO) + "]"
				cDmp += " CTX=["  + AllTrim(SX3->X3_CONTEXT) + "]"
				cDmp += CRLF
			EndIf
		EndIf

		SX3->(DbSkip())
	EndDo

Return "  columnas del browse: " + cValToChar(nN) + " ajustadas" + ;
       " (de " + cValToChar(nV) + " campos vistos)" + CRLF + cDmp

// ---------------------------------------------------------------------
Static Function DicHayTb(cFis)
	Local nRet := 0

	BeginSql Alias "QT"
		SELECT COUNT(*) AS TOT FROM ALL_TABLES WHERE TABLE_NAME = %Exp:cFis%
	EndSql
	QT->(DbGoTop())
	nRet := QT->TOT
	QT->(DbCloseArea())

Return nRet > 0

// ---------------------------------------------------------------------
// SX2 clonando el registro de ZA1, que ya es una tabla custom correcta.
//
// Los modos de acceso quedan en Compartido desde aqui. En el Anexo 20
// habia que ponerlos a mano en cada tabla y se olvidaba.
// ---------------------------------------------------------------------
Static Function DicSX2(cAli, cFis, cNom, cChav)
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

	DicPon("SX2", "X2_MODO",    "C")
	DicPon("SX2", "X2_MODOUN",  "C")
	DicPon("SX2", "X2_MODOEMP", "C")

	SX2->(MsUnlock())

Return "  SX2: creado (modos en Compartido)" + CRLF

// ---------------------------------------------------------------------
// Pone un valor solo si el campo existe en este ambiente.
// ---------------------------------------------------------------------
Static Function DicPon(cAlias, cCampo, xVal)
	Local nPos := (cAlias)->(FieldPos(cCampo))

	If nPos > 0
		(cAlias)->(FieldPut(nPos, xVal))
	EndIf

Return

// ---------------------------------------------------------------------
// SX3 clonando campos molde de ZA1: uno de caracter y uno de fecha.
// Para los numericos se parte del molde de caracter y se cambia el tipo,
// el tamano, los decimales y la mascara.
// ---------------------------------------------------------------------
Static Function DicSX3(cAli, aCpo)
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
		If DicHayCp(cAli, aCpo[nI][1])
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

		DicPon("SX3", "X3_BROWSE", DicVis(aCpo[nI]))
		DicPon("SX3", "X3_DESCRIC", aCpo[nI][5])
		DicPon("SX3", "X3_DESCSPA", aCpo[nI][5])
		DicPon("SX3", "X3_DESCENG", aCpo[nI][5])

		If aCpo[nI][2] == "N"
			DicPon("SX3", "X3_PICTURE", DicMasc(aCpo[nI]))
		EndIf

		SX3->(MsUnlock())
		nNue++
	Next nI

Return "  SX3: " + cValToChar(nNue) + " campos nuevos" + CRLF

// ---------------------------------------------------------------------
// Que campos salen como columna del browse: NINGUNO.
//
// Las columnas del visor se definen a mano en ZCFDIVIS (VisCols), con su
// titulo, su ancho y su valor ya traducido -- "ingreso" en vez de "I",
// la fecha formateada, el total con comas. Eso el diccionario no lo hace.
//
// Si ademas se marcan campos con X3_BROWSE = 'S', Protheus pinta LOS DOS
// juegos y las columnas salen duplicadas. Paso exactamente eso.
//
// La "S" que traen algunos campos en la definicion se deja como
// documentacion de cuales interesan, pero aqui ya no se usa.
// ---------------------------------------------------------------------
Static Function DicVis(aCpo)
	Local lDoc := (Len(aCpo) >= 6 .And. aCpo[6] == "S")
Return IIf(lDoc, "N", "N")

// ---------------------------------------------------------------------
// Mascara de un campo numerico segun sus decimales.
// ---------------------------------------------------------------------
Static Function DicMasc(aCpo)
	Local cRet := "@E 999,999,999"
	Local nI   := 0

	If aCpo[4] > 0
		cRet += "."
		For nI := 1 To aCpo[4]
			cRet += "9"
		Next nI
	EndIf

Return cRet

// ---------------------------------------------------------------------
// Se arma el nombre de la tabla a mano en vez de usar %Table:SX3%: no
// esta verificado que ese macro resuelva para tablas del diccionario, y
// la version de ANX20ADM que si funciono lo hacia asi.
Static Function DicHayCp(cAli, cCampo)
	Local nRet := 0
	Local cSql := ""

	cSql := "SELECT COUNT(*) AS TOT FROM " + DicFis("SX3") + " "
	cSql += "WHERE D_E_L_E_T_ = ' ' "
	cSql += "AND TRIM(X3_ARQUIVO) = '" + AllTrim(cAli) + "' "
	cSql += "AND TRIM(X3_CAMPO) = '" + AllTrim(cCampo) + "'"

	TCQuery cSql New Alias "QC"
	QC->(DbGoTop())
	nRet := QC->TOT
	QC->(DbCloseArea())

Return nRet > 0

// ---------------------------------------------------------------------
Static Function DicSIX(cAli, cChav)
	Local nHay := 0
	Local nRet := 0
	Local cFis := DicFis("SIX")
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
