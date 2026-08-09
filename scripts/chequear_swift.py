#!/usr/bin/env python3
"""Chequeo rápido de balance de llaves/paréntesis/corchetes en Swift.

No hay Xcode en el entorno donde se escribe el código de Maratonia, así
que este script es la primera línea de defensa antes de commitear:
recorre cada archivo carácter por carácter entendiendo comentarios
(// y /* */ anidados) y strings ("...", multilínea \"\"\"...\"\"\" e
interpolación \\( ) ), y verifica que los delimitadores cierren.

Un desbalance acá es casi seguro un error de edición que rompería la
compilación en la Mac. (La versión anterior usaba regex y daba falsos
positivos con comillas sueltas dentro de comentarios.)

Uso: python3 scripts/chequear_swift.py
"""

import glob
import sys


def limpiar(codigo: str) -> str:
    """Devuelve el código sin comentarios ni contenido de strings."""
    resultado = []
    i = 0
    n = len(codigo)
    while i < n:
        c = codigo[i]
        # Comentario de línea
        if c == "/" and i + 1 < n and codigo[i + 1] == "/":
            while i < n and codigo[i] != "\n":
                i += 1
            continue
        # Comentario de bloque (Swift permite anidarlos)
        if c == "/" and i + 1 < n and codigo[i + 1] == "*":
            profundidad = 1
            i += 2
            while i < n and profundidad > 0:
                if codigo.startswith("/*", i):
                    profundidad += 1
                    i += 2
                elif codigo.startswith("*/", i):
                    profundidad -= 1
                    i += 2
                else:
                    i += 1
            continue
        # String multilínea
        if codigo.startswith('"""', i):
            i += 3
            while i < n and not codigo.startswith('"""', i):
                if codigo[i] == "\\":
                    i += 2
                else:
                    i += 1
            i += 3
            continue
        # String simple (la interpolación \(...) se deja pasar como
        # escape: sus paréntesis internos quedan fuera del conteo, lo
        # cual es conservador y suficiente para detectar ediciones rotas)
        if c == '"':
            i += 1
            while i < n and codigo[i] != '"':
                if codigo[i] == "\\":
                    i += 2
                else:
                    i += 1
            i += 1
            continue
        resultado.append(c)
        i += 1
    return "".join(resultado)


def main() -> int:
    archivos = sorted(
        glob.glob("Maraton/*.swift")
        + glob.glob("Maraton Watch App/*.swift")
        + glob.glob("Shared/*.swift")
        + glob.glob("Tests/MaratonTests/*.swift")
    )
    fallas = []
    for ruta in archivos:
        with open(ruta, encoding="utf-8") as f:
            limpio = limpiar(f.read())
        for abre, cierra in [("{", "}"), ("(", ")"), ("[", "]")]:
            if limpio.count(abre) != limpio.count(cierra):
                fallas.append((ruta, abre, limpio.count(abre), limpio.count(cierra)))
    if fallas:
        for ruta, simbolo, a, c in fallas:
            print(f"DESBALANCE {ruta}: {simbolo} abre {a} vs cierra {c}")
        return 1
    print(f"{len(archivos)} archivos Swift balanceados")
    return 0


if __name__ == "__main__":
    sys.exit(main())
