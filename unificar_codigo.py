import os

# Extensiones a incluir
extensions = ['.dart', '.yaml', '.md', '.drift', '.arb']

# Carpetas a ignorar
ignore_dirs = {'.dart_tool', '.idea', 'build', 'ios', 'android', 'web', 'macos', 'windows', 'linux', 'test', '.git'}

# Archivos específicos a ignorar
ignore_files = {'pubspec.lock', 'codigos_unificados.txt', 'unificar_codigo.py'}

output_file = 'CODIGO_COMPLETO.txt'

def is_generated_file(filename):
    """Detecta archivos generados automáticamente por build_runner."""
    return filename.endswith('.g.dart') or filename.endswith('.freezed.dart')

def generate_tree(startpath):
    """Genera una representación visual del árbol de archivos."""
    tree_str = "--- PROJECT STRUCTURE ---\n"
    for root, dirs, files in os.walk(startpath):
        # Filtrar directorios ignorados in-place
        dirs[:] = [d for d in dirs if d not in ignore_dirs]
        
        level = root.replace(startpath, '').count(os.sep)
        indent = ' ' * 4 * (level)
        tree_str += f"{indent}{os.path.basename(root)}/\n"
        subindent = ' ' * 4 * (level + 1)
        for f in files:
            # Filtramos extensiones, archivos ignorados y archivos generados
            if (any(f.endswith(ext) for ext in extensions) 
                and f not in ignore_files 
                and not is_generated_file(f)):
                 tree_str += f"{subindent}{f}\n"
    tree_str += "-------------------------\n\n"
    return tree_str

# Ejecución
print("Generando archivo unificado...")

with open(output_file, 'w', encoding='utf-8') as outfile:
    # 1. Escribir la estructura del árbol
    outfile.write(generate_tree('.'))

    # 2. Escribir el contenido de los archivos
    for root, dirs, files in os.walk('.'):
        # Optimización: Modificar dirs in-place evita entrar en carpetas ignoradas
        dirs[:] = [d for d in dirs if d not in ignore_dirs]

        for file in files:
            # Verificaciones de filtrado
            has_valid_ext = any(file.endswith(ext) for ext in extensions)
            is_ignored = file in ignore_files
            is_generated = is_generated_file(file)

            if has_valid_ext and not is_ignored and not is_generated:
                file_path = os.path.join(root, file)
                
                # Encabezado claro para el archivo
                outfile.write(f"\n\n--- START FILE: {file_path} ---\n")
                try:
                    with open(file_path, 'r', encoding='utf-8') as infile:
                        outfile.write(infile.read())
                except Exception as e:
                    outfile.write(f"Error reading file: {e}")
                outfile.write(f"\n--- END FILE: {file_path} ---\n")

print(f"¡Listo! Se ha creado '{output_file}' excluyendo archivos generados (.g.dart, .freezed.dart).")
print("Sube este archivo al chat para comenzar.")