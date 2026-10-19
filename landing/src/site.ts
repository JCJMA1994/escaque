/** Configuración de la landing. Revisa los valores marcados antes de publicar. */
export const site = {
  name: 'Escaque',
  title: 'Escaque: Ajedrez y Damas',
  description:
    'Ajedrez y damas con las reglas de sus reglamentos oficiales. Contra la IA, en el mismo teléfono u online con amigos.',
  descriptionEn:
    'Chess and draughts with the rules of their official rulebooks. Against the AI, on the same phone or online with friends.',
  // Entorno: dev, qa o prod. En qa la web no se indexa.
  env: (import.meta.env.PUBLIC_ENV ?? 'dev') as 'dev' | 'qa' | 'prod',
  // REVISAR: applicationId real de Play Store.
  playUrl: 'https://play.google.com/store/apps/details?id=com.tuempresa.escaque',
  // REVISAR: crea este buzón antes de publicar.
  email: 'escaque@system-failed-tech.com',
  // REVISAR: titular de los datos (persona o empresa) para la política de privacidad.
  owner: '[Nombre o razón social del titular]',
  // REVISAR: documento (DNI o RUC) y domicilio del titular.
  ownerId: '[DNI o RUC]',
  ownerAddress: '[Domicilio]',
  // REVISAR: inscripción del banco de datos en el Registro Nacional de Protección
  // de Datos Personales (Perú), si corresponde.
  dataBankRegistration: '[N.º de inscripción del banco de datos «Usuarios de Escaque»]',
  updated: '18 de octubre de 2026',
  updatedEn: 'October 18, 2026',
};

export const indexable = site.env === 'prod';
