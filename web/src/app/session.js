// Única puerta a la clave de acceso (AUTH-02). Sólo sessionStorage: muere con la pestaña.
// Nunca en la URL, en localStorage, en variables de build ni en el bundle.
const KEY = 'cingula.key';

export const getKey = () => sessionStorage.getItem(KEY);
export const setKey = (key) => sessionStorage.setItem(KEY, key);
export const clearKey = () => sessionStorage.removeItem(KEY);
