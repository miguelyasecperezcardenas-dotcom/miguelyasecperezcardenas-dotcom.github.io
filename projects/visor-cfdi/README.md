# Visor de CFDI — ADVPL TOTVS (Módulo Financiero)

**CFDI Viewer — ADVPL TOTVS (Financial Module)**

## Español

Visor de CFDI desarrollado en ADVPL para TOTVS Protheus, dentro del módulo Financiero. Permite consultar el acervo de comprobantes fiscales a partir de los XML, sin modificar la operación base en su primera versión (solo lectura).

### Qué incluye

- **Punto de entrada único:** una sola entrada de menú en Protheus desde la que se accede a las demás rutinas.
- **Inventario y censo de XML:** localiza en el servidor qué carpetas contienen XML de CFDI y qué nodos y atributos traen realmente los archivos, antes de diseñar el diccionario de datos.
- **Diccionario de datos:** tablas para cabecera del CFDI, conceptos, impuestos, complemento de pagos y conciliación contra Protheus, con alta en el diccionario estándar (SX2, SX3, SIX).
- **Ingesta de XML:** importación de archivos XML al visor con parser de XML, idempotente por UUID (se puede correr varias veces sin duplicar) y tolerante a archivos con error (registra el fallo y continúa).
- **Navegación y detalle:** browse de comprobantes con filtros y leyenda por estatus/tipo, y vista de detalle con cabecera, conceptos e impuestos en nivel comprobante y nivel concepto.
- **Partidas del comprobante:** consulta de conceptos, impuestos, pagos, comercio exterior y relacionados del folio seleccionado.
- **Catálogos del SAT:** descripciones legibles para claves de forma de pago, método, régimen, uso de CFDI, clave producto/servicio y unidad, con caché en memoria y carga desde CSV para los catálogos grandes.
- **Conciliación PPD:** identifica facturas a crédito (PPD) cobradas sin su complemento de pago, cruzando el acervo del visor contra Protheus (facturación y cobranza).
- **Control de complementos:** detección de complementos de pago a medio emitir (folio fiscal sin fecha de timbrado) en cobranza.
- **Representación impresa:** localiza y abre el PDF del comprobante seleccionado a partir de su XML.
- **Estatus ante el SAT:** consulta del estatus del CFDI (vigente / cancelado / no encontrado) y su cancelabilidad.
- **Exportación:** generación de archivos para Excel (comprobantes, conceptos y pagos) en formato CSV compatible con Excel en español.

### Tecnologías

ADVPL · TOTVS Protheus · TopConnect / Oracle · XmlParser · FWMBrowse · CFDI 4.0 · Catálogos del SAT

### Notas

- Código fuente sanitizado en [`src/`](src/): se eliminaron nombre del cliente, rutas y cifras internas. La lógica del visor se conserva para fines de portafolio.
- Cliente y capturas: por confirmar.

---

## English

CFDI viewer developed in ADVPL for TOTVS Protheus, in the Financial module. It lets users query the fiscal document repository built from XML files, read-only in its first version (it does not record, alter or delete base-operation data).

### What it includes

- **Single entry point:** one Protheus menu entry from which the other routines are accessed.
- **XML inventory and census:** locates which server folders actually contain CFDI XML files and which nodes and attributes the real files carry, before designing the data dictionary.
- **Data dictionary:** tables for the CFDI header, concepts, taxes, payment complement and reconciliation against Protheus, registered in the standard dictionary (SX2, SX3, SIX).
- **XML ingestion:** XML import into the viewer with an XML parser, idempotent by UUID (safe to run repeatedly without duplicates) and tolerant to bad files (logs the failure and continues).
- **Navigation and detail:** CFDI browse with filters and a status/type legend, plus a detail view with header, concepts and taxes at both document and concept level.
- **Document lines:** concepts, taxes, payments, foreign trade and related documents for the selected fiscal folio.
- **SAT catalogs:** readable descriptions for payment form, method, regime, CFDI use, product/service key and unit, with in-memory cache and CSV loading for large catalogs.
- **PPD reconciliation:** identifies credit invoices (PPD) that were collected without their payment complement, cross-checking the viewer repository against Protheus billing and collections.
- **Payment complement control:** detection of half-issued payment complements (fiscal folio without stamp date) in collections.
- **Printed representation:** locates and opens the PDF of the selected document from its XML.
- **SAT status:** CFDI status query (valid / cancelled / not found) and cancellability.
- **Export:** Excel-ready files (documents, concepts and payments) in CSV format compatible with Spanish-locale Excel.

### Technologies

ADVPL · TOTVS Protheus · TopConnect / Oracle · XmlParser · FWMBrowse · CFDI 4.0 · SAT catalogs

### Notes

- Sanitized source code in [`src/`](src/): client name, internal paths and figures were removed. The viewer logic is preserved for portfolio purposes.
- Client and screenshots: to be confirmed.
