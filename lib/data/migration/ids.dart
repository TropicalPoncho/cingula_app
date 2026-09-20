import 'package:uuid/uuid.dart';

/// Namespace fijo de Cingula. Generado una sola vez; NUNCA cambiar: los uuid v5
/// derivados de el son la identidad de las obras y portales que crean, por
/// separado y sin hablarse, la migracion del celular y el script de Neon (D-24).
const String cingulaNamespace = '6f1a6c3e-9b54-4b2a-8f3d-1d0c9a7e5b21';

String obraUuidForPath(String pathUuid) =>
    const Uuid().v5(cingulaNamespace, 'obra:$pathUuid');

String portalUuidForTrigger(String triggerUuid) =>
    const Uuid().v5(cingulaNamespace, 'portal:$triggerUuid');
