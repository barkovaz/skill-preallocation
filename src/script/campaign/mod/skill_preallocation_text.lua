-- Skill Pre-Allocation: the mod's own texts, in the 13 languages the game ships with.
--
-- The game tells scripts its language through the context function LocLanguage; the mod reads it
-- the first time one of the player's characters is shown in the skills panel and uses English when
-- the language is unknown or can't be read. Texts are plain UTF-8 (the game's Lua handles UTF-8
-- strings: its string.len / string.sub / string.find count characters).
--
-- TEXT.get(key, ...) returns the text in the game's language, formatted with string.format when
-- arguments are given. An entry can be { one = ..., other = ... }: the first argument picks the form
-- (1 = one). Polish, Russian and Czech put the number after a colon or in brackets instead, which needs
-- no plural.
--
-- Keys: select / no_presets (the presets dropdown), button_tip (its tooltip), badge_tip (the numbers on
-- the skill cards; badge_tip_click: that tooltip's second line, a click on them removes a point), tip_* (the icon buttons' tooltips; spend when points can be allocated now; tip_plan /
-- tip_plan_on the plan mode button off / on; *_plan: the same button in plan mode), ask_* (the
-- confirmations), heading_* (the name dialog), default_name (a new preset's suggested name).

SKILL_PREALLOCATION = SKILL_PREALLOCATION or {}
local SPA = SKILL_PREALLOCATION
local TEXT = {}
SPA.text = TEXT

local S = {}
TEXT.strings = S

-- English (also the fallback for anything missing)
S.en = {
	select = "Select preset",
	no_presets = "No presets",
	button_tip = "Skill tree presets for this character type,\n"
		.. "shared by all campaigns.\n"
		.. "Left-click a skill to pre-allocate it,\n"
		.. "left-click its rank numbers to remove a point.",
	badge_tip = "Pre-allocated: learned at rank %s",
	badge_tip_click = "Click here to remove the last pre-allocated point",
	tip_new = "Save as new preset",
	tip_overwrite = "Overwrite the selected preset",
	tip_rename = "Rename the selected preset",
	tip_delete = "Delete the selected preset",
	tip_clear = "Clear pre-allocations",
	spend = { one = "Allocate %d point now", other = "Allocate %d points now" },
	tip_spend = "Allocate free skill points to the pre-allocated skills now",
	ask_overwrite = "Overwrite the preset \"%s\"?",
	ask_delete = "Delete the preset \"%s\"?",
	ask_clear = "Clear all pre-allocations?",
	ask_spend = { one = "Allocate %d point now?", other = "Allocate %d points now?" },
	heading_save = "Save as new preset",
	heading_rename = "Rename preset",
	tip_plan = "Plan mode: plan a build from rank 1 on an\nempty skill tree. Nothing is learned while it\nis on. When you leave it, a build you planned\nbecomes the pre-allocations.",
	tip_plan_on = "Leave plan mode: the build becomes the\npre-allocations (skills already learned are\nskipped). An empty build changes nothing.",
	tip_spend_plan = "Leave plan mode to allocate points",
	tip_clear_plan = "Clear the build (start from scratch)",
	ask_clear_plan = "Clear the whole build and start from scratch?",
	default_name = "Build",
}

-- French
S.fr = {
	select = "Choisir un préréglage",
	no_presets = "Aucun préréglage",
	button_tip = "Préréglages d'arbre de compétences pour ce type\n"
		.. "de personnage, communs à toutes les campagnes.\n"
		.. "Clic gauche sur une compétence pour la planifier,\n"
		.. "clic gauche sur ses numéros de rang\n"
		.. "pour retirer un point.",
	badge_tip = "Planifiée : apprise au rang %s",
	badge_tip_click = "Cliquez ici pour retirer le dernier point planifié",
	tip_new = "Enregistrer comme nouveau préréglage",
	tip_overwrite = "Écraser le préréglage sélectionné",
	tip_rename = "Renommer le préréglage sélectionné",
	tip_delete = "Supprimer le préréglage sélectionné",
	tip_clear = "Effacer la planification",
	spend = { one = "Attribuer %d point maintenant", other = "Attribuer %d points maintenant" },
	tip_spend = "Attribuer maintenant les points libres aux compétences planifiées",
	ask_overwrite = "Écraser le préréglage « %s » ?",
	ask_delete = "Supprimer le préréglage « %s » ?",
	ask_clear = "Effacer toute la planification ?",
	ask_spend = { one = "Attribuer %d point maintenant ?", other = "Attribuer %d points maintenant ?" },
	heading_save = "Enregistrer comme nouveau préréglage",
	heading_rename = "Renommer le préréglage",
	tip_plan = "Mode planification : planifier un arbre\ndepuis le rang 1 sur un arbre vierge. Rien\nn'est appris dans ce mode. En le quittant,\nl'arbre planifié remplace la planification.",
	tip_plan_on = "Quitter le mode planification : l'arbre\nplanifié remplace la planification (les\ncompétences déjà apprises sont ignorées).\nUn arbre vide ne change rien.",
	tip_spend_plan = "Quittez le mode planification pour attribuer des points",
	tip_clear_plan = "Effacer l'arbre planifié (repartir de zéro)",
	ask_clear_plan = "Effacer tout l'arbre planifié et repartir de zéro ?",
	default_name = "Préréglage",
}

-- German
S.ge = {
	select = "Vorlage wählen",
	no_presets = "Keine Vorlagen",
	button_tip = "Vorlagen für den Fertigkeitsbaum dieses\n"
		.. "Charaktertyps, in allen Kampagnen verfügbar.\n"
		.. "Linksklick auf eine Fertigkeit merkt sie vor,\n"
		.. "Linksklick auf ihre Rangzahlen\n"
		.. "entfernt einen Punkt.",
	badge_tip = "Vorgemerkt: wird auf Rang %s gelernt",
	badge_tip_click = "Hier klicken, um den letzten vorgemerkten Punkt zu entfernen",
	tip_new = "Als neue Vorlage speichern",
	tip_overwrite = "Ausgewählte Vorlage überschreiben",
	tip_rename = "Ausgewählte Vorlage umbenennen",
	tip_delete = "Ausgewählte Vorlage löschen",
	tip_clear = "Vormerkungen löschen",
	spend = { one = "Jetzt %d Punkt zuweisen", other = "Jetzt %d Punkte zuweisen" },
	tip_spend = "Freie Fertigkeitspunkte jetzt den vorgemerkten Fertigkeiten zuweisen",
	ask_overwrite = "Vorlage „%s“ überschreiben?",
	ask_delete = "Vorlage „%s“ löschen?",
	ask_clear = "Alle Vormerkungen löschen?",
	ask_spend = { one = "Jetzt %d Punkt zuweisen?", other = "Jetzt %d Punkte zuweisen?" },
	heading_save = "Als neue Vorlage speichern",
	heading_rename = "Vorlage umbenennen",
	tip_plan = "Planungsmodus: einen Baum ab Rang 1 auf\neinem leeren Fertigkeitenbaum planen. Dabei\nwird nichts gelernt. Beim Verlassen wird der\nPlan zu den Vormerkungen.",
	tip_plan_on = "Planungsmodus verlassen: der Plan wird zu\nden Vormerkungen (bereits gelernte\nFertigkeiten werden übersprungen). Ein\nleerer Plan ändert nichts.",
	tip_spend_plan = "Zum Zuweisen den Planungsmodus verlassen",
	tip_clear_plan = "Plan löschen (neu beginnen)",
	ask_clear_plan = "Den ganzen Plan löschen und neu beginnen?",
	default_name = "Vorlage",
}

-- Italian
S.it = {
	select = "Scegli un preset",
	no_presets = "Nessun preset",
	button_tip = "Preset dell'albero delle abilità per questo tipo\n"
		.. "di personaggio, condivisi da tutte le campagne.\n"
		.. "Clic sinistro su un'abilità per preassegnarla,\n"
		.. "clic sinistro sui suoi numeri di livello\n"
		.. "per togliere un punto.",
	badge_tip = "Preassegnata: appresa al livello %s",
	badge_tip_click = "Fai clic qui per rimuovere l'ultimo punto preassegnato",
	tip_new = "Salva come nuovo preset",
	tip_overwrite = "Sovrascrivi il preset selezionato",
	tip_rename = "Rinomina il preset selezionato",
	tip_delete = "Elimina il preset selezionato",
	tip_clear = "Cancella le preassegnazioni",
	spend = { one = "Assegna %d punto ora", other = "Assegna %d punti ora" },
	tip_spend = "Assegna ora i punti abilità liberi alle abilità preassegnate",
	ask_overwrite = "Sovrascrivere il preset «%s»?",
	ask_delete = "Eliminare il preset «%s»?",
	ask_clear = "Cancellare tutte le preassegnazioni?",
	ask_spend = { one = "Assegnare %d punto ora?", other = "Assegnare %d punti ora?" },
	heading_save = "Salva come nuovo preset",
	heading_rename = "Rinomina il preset",
	tip_plan = "Modalità pianificazione: pianifica un albero\ndal livello 1 su un albero vuoto. In questa\nmodalità non si apprende nulla. Uscendo, il\npiano diventa le preassegnazioni.",
	tip_plan_on = "Esci dalla modalità pianificazione: il piano\ndiventa le preassegnazioni (le abilità già\napprese vengono saltate). Un piano vuoto non\ncambia nulla.",
	tip_spend_plan = "Esci dalla modalità pianificazione per assegnare i punti",
	tip_clear_plan = "Cancella il piano (riparti da zero)",
	ask_clear_plan = "Cancellare l'intero piano e ripartire da zero?",
	default_name = "Preset",
}

-- Spanish (Spain)
S.sp = {
	select = "Elegir plantilla",
	no_presets = "No hay plantillas",
	button_tip = "Plantillas del árbol de habilidades para este\n"
		.. "tipo de personaje, comunes a todas las campañas.\n"
		.. "Clic izquierdo en una habilidad para preasignarla;\n"
		.. "clic izquierdo en sus números de rango\n"
		.. "para quitar un punto.",
	badge_tip = "Preasignada: se aprende en el rango %s",
	badge_tip_click = "Haz clic aquí para quitar el último punto preasignado",
	tip_new = "Guardar como nueva plantilla",
	tip_overwrite = "Sobrescribir la plantilla seleccionada",
	tip_rename = "Renombrar la plantilla seleccionada",
	tip_delete = "Borrar la plantilla seleccionada",
	tip_clear = "Borrar las preasignaciones",
	spend = { one = "Asignar %d punto ahora", other = "Asignar %d puntos ahora" },
	tip_spend = "Asignar ahora los puntos de habilidad libres a las habilidades preasignadas",
	ask_overwrite = "¿Sobrescribir la plantilla «%s»?",
	ask_delete = "¿Borrar la plantilla «%s»?",
	ask_clear = "¿Borrar todas las preasignaciones?",
	ask_spend = { one = "¿Asignar %d punto ahora?", other = "¿Asignar %d puntos ahora?" },
	heading_save = "Guardar como nueva plantilla",
	heading_rename = "Renombrar plantilla",
	tip_plan = "Modo planificación: planifica un árbol desde\nel rango 1 sobre un árbol vacío. En este modo\nno se aprende nada. Al salir, el plan pasa a\nser las preasignaciones.",
	tip_plan_on = "Salir del modo planificación: el plan pasa a\nser las preasignaciones (las habilidades ya\naprendidas se omiten). Un plan vacío no\ncambia nada.",
	tip_spend_plan = "Sal del modo planificación para asignar puntos",
	tip_clear_plan = "Borrar el plan (empezar de cero)",
	ask_clear_plan = "¿Borrar todo el plan y empezar de cero?",
	default_name = "Plantilla",
}

-- Polish
S.pl = {
	select = "Wybierz szablon",
	no_presets = "Brak szablonów",
	button_tip = "Szablony drzewka umiejętności dla tego typu\n"
		.. "postaci, wspólne dla wszystkich kampanii.\n"
		.. "Kliknij umiejętność lewym przyciskiem,\n"
		.. "aby ją zaplanować, a jej numery poziomów,\n"
		.. "aby usunąć punkt.",
	badge_tip = "Zaplanowano: nauka na poziomie %s",
	badge_tip_click = "Kliknij tutaj, aby usunąć ostatni zaplanowany punkt",
	tip_new = "Zapisz jako nowy szablon",
	tip_overwrite = "Nadpisz wybrany szablon",
	tip_rename = "Zmień nazwę wybranego szablonu",
	tip_delete = "Usuń wybrany szablon",
	tip_clear = "Wyczyść zaplanowane punkty",
	spend = "Rozdziel punkty teraz: %d",
	tip_spend = "Rozdziel teraz wolne punkty na zaplanowane umiejętności",
	ask_overwrite = "Nadpisać szablon „%s”?",
	ask_delete = "Usunąć szablon „%s”?",
	ask_clear = "Wyczyścić wszystkie zaplanowane punkty?",
	ask_spend = "Rozdzielić teraz zaplanowane punkty (%d)?",
	heading_save = "Zapisz jako nowy szablon",
	heading_rename = "Zmień nazwę szablonu",
	tip_plan = "Tryb planowania: zaplanuj drzewko od\npoziomu 1 na pustym drzewku. W tym trybie\nnic nie jest uczone. Po wyjściu plan staje\nsię zaplanowanymi punktami.",
	tip_plan_on = "Wyjdź z trybu planowania: plan staje się\nzaplanowanymi punktami (już poznane\numiejętności są pomijane). Pusty plan\nniczego nie zmienia.",
	tip_spend_plan = "Wyjdź z trybu planowania, aby rozdzielić punkty",
	tip_clear_plan = "Wyczyść plan (zacznij od nowa)",
	ask_clear_plan = "Wyczyścić cały plan i zacząć od nowa?",
	default_name = "Szablon",
}

-- Russian
S.ru = {
	select = "Выбрать шаблон",
	no_presets = "Нет шаблонов",
	button_tip = "Шаблоны дерева навыков для этого типа\n"
		.. "персонажей, общие для всех кампаний.\n"
		.. "ЛКМ по навыку — запланировать очко;\n"
		.. "ЛКМ по номерам уровней — убрать очко.",
	badge_tip = "Запланировано: изучение на уровне %s",
	badge_tip_click = "Нажмите здесь, чтобы убрать последнее запланированное очко",
	tip_new = "Сохранить как новый шаблон",
	tip_overwrite = "Перезаписать выбранный шаблон",
	tip_rename = "Переименовать выбранный шаблон",
	tip_delete = "Удалить выбранный шаблон",
	tip_clear = "Очистить запланированные очки",
	spend = "Распределить очки сейчас: %d",
	tip_spend = "Распределить свободные очки по запланированным навыкам сейчас",
	ask_overwrite = "Перезаписать шаблон «%s»?",
	ask_delete = "Удалить шаблон «%s»?",
	ask_clear = "Очистить все запланированные очки?",
	ask_spend = "Распределить запланированные очки сейчас (%d)?",
	heading_save = "Сохранить как новый шаблон",
	heading_rename = "Переименовать шаблон",
	tip_plan = "Режим планирования: спланировать дерево\nс 1-го уровня на пустом дереве навыков.\nВ этом режиме ничего не изучается. При\nвыходе план становится запланированными\nочками.",
	tip_plan_on = "Выйти из режима планирования: план\nстановится запланированными очками (уже\nизученные навыки пропускаются). Пустой\nплан ничего не меняет.",
	tip_spend_plan = "Выйдите из режима планирования, чтобы распределить очки",
	tip_clear_plan = "Очистить план (начать заново)",
	ask_clear_plan = "Очистить весь план и начать заново?",
	default_name = "Шаблон",
}

-- Czech
S.cz = {
	select = "Vybrat šablonu",
	no_presets = "Žádné šablony",
	button_tip = "Šablony stromu dovedností pro tento typ\n"
		.. "postavy, společné pro všechny kampaně.\n"
		.. "Levým kliknutím na dovednost ji naplánujete;\n"
		.. "levým kliknutím na čísla úrovní odeberete bod.",
	badge_tip = "Naplánováno: postava se ji naučí na úrovni %s",
	badge_tip_click = "Kliknutím sem odeberete poslední naplánovaný bod",
	tip_new = "Uložit jako novou šablonu",
	tip_overwrite = "Přepsat vybranou šablonu",
	tip_rename = "Přejmenovat vybranou šablonu",
	tip_delete = "Smazat vybranou šablonu",
	tip_clear = "Vymazat naplánované body",
	spend = "Přidělit body nyní: %d",
	tip_spend = "Přidělit nyní volné body naplánovaným dovednostem",
	ask_overwrite = "Přepsat šablonu „%s“?",
	ask_delete = "Smazat šablonu „%s“?",
	ask_clear = "Vymazat všechny naplánované body?",
	ask_spend = "Přidělit naplánované body nyní (%d)?",
	heading_save = "Uložit jako novou šablonu",
	heading_rename = "Přejmenovat šablonu",
	tip_plan = "Režim plánování: naplánujte strom od\núrovně 1 na prázdném stromu dovedností.\nV tomto režimu se nic nenaučí. Po opuštění\nse plán stane naplánovanými body.",
	tip_plan_on = "Opustit režim plánování: plán se stane\nnaplánovanými body (již naučené\ndovednosti se přeskočí). Prázdný plán nic\nnezmění.",
	tip_spend_plan = "Pro přidělení bodů opusťte režim plánování",
	tip_clear_plan = "Vymazat plán (začít znovu)",
	ask_clear_plan = "Vymazat celý plán a začít znovu?",
	default_name = "Šablona",
}

-- Turkish
S.tr = {
	select = "Şablon seç",
	no_presets = "Şablon yok",
	button_tip = "Bu karakter türü için yetenek ağacı şablonları,\n"
		.. "tüm kampanyalarda ortaktır.\n"
		.. "Planlamak için bir yeteneğe sol tıklayın;\n"
		.. "bir puanı kaldırmak için seviye\n"
		.. "numaralarına sol tıklayın.",
	badge_tip = "Planlandı: öğrenileceği seviye %s",
	badge_tip_click = "Son planlanan puanı kaldırmak için buraya tıklayın",
	tip_new = "Yeni şablon olarak kaydet",
	tip_overwrite = "Seçili şablonun üzerine yaz",
	tip_rename = "Seçili şablonu yeniden adlandır",
	tip_delete = "Seçili şablonu sil",
	tip_clear = "Planlanan puanları temizle",
	spend = "%d puanı şimdi dağıt",
	tip_spend = "Boş yetenek puanlarını şimdi planlanan yeteneklere dağıt",
	ask_overwrite = "\"%s\" şablonunun üzerine yazılsın mı?",
	ask_delete = "\"%s\" şablonu silinsin mi?",
	ask_clear = "Planlanan tüm puanlar temizlensin mi?",
	ask_spend = "%d puan şimdi dağıtılsın mı?",
	heading_save = "Yeni şablon olarak kaydet",
	heading_rename = "Şablonu yeniden adlandır",
	tip_plan = "Planlama modu: boş bir yetenek ağacında\n1. seviyeden bir ağaç planla. Bu modda\nhiçbir şey öğrenilmez. Moddan çıkınca plan,\nplanlanan puanlara dönüşür.",
	tip_plan_on = "Planlama modundan çık: plan, planlanan\npuanlara dönüşür (zaten öğrenilmiş\nyetenekler atlanır). Boş bir plan hiçbir\nşeyi değiştirmez.",
	tip_spend_plan = "Puan dağıtmak için planlama modundan çıkın",
	tip_clear_plan = "Planı temizle (baştan başla)",
	ask_clear_plan = "Tüm plan temizlenip baştan başlansın mı?",
	default_name = "Şablon",
}

-- Brazilian Portuguese
S.br = {
	select = "Escolher predefinição",
	no_presets = "Nenhuma predefinição",
	button_tip = "Predefinições da árvore de habilidades para\n"
		.. "este tipo de personagem, compartilhadas\n"
		.. "por todas as campanhas.\n"
		.. "Clique esquerdo: pré-alocar a habilidade;\n"
		.. "clique esquerdo nos números de nível:\n"
		.. "remover um ponto.",
	badge_tip = "Pré-alocada: aprendida no nível %s",
	badge_tip_click = "Clique aqui para remover o último ponto pré-alocado",
	tip_new = "Salvar como nova predefinição",
	tip_overwrite = "Sobrescrever a predefinição selecionada",
	tip_rename = "Renomear a predefinição selecionada",
	tip_delete = "Excluir a predefinição selecionada",
	tip_clear = "Limpar pré-alocações",
	spend = { one = "Alocar %d ponto agora", other = "Alocar %d pontos agora" },
	tip_spend = "Alocar agora os pontos de habilidade livres nas habilidades pré-alocadas",
	ask_overwrite = "Sobrescrever a predefinição \"%s\"?",
	ask_delete = "Excluir a predefinição \"%s\"?",
	ask_clear = "Limpar todas as pré-alocações?",
	ask_spend = { one = "Alocar %d ponto agora?", other = "Alocar %d pontos agora?" },
	heading_save = "Salvar como nova predefinição",
	heading_rename = "Renomear predefinição",
	tip_plan = "Modo de planejamento: planeje uma árvore\ndesde o nível 1 sobre uma árvore vazia. Nada\né aprendido neste modo. Ao sair, o plano\nvira as pré-alocações.",
	tip_plan_on = "Sair do modo de planejamento: o plano vira\nas pré-alocações (habilidades já aprendidas\nsão ignoradas). Um plano vazio não muda\nnada.",
	tip_spend_plan = "Saia do modo de planejamento para alocar pontos",
	tip_clear_plan = "Limpar o plano (começar do zero)",
	ask_clear_plan = "Limpar o plano inteiro e começar do zero?",
	default_name = "Predefinição",
}

-- Korean
S.kr = {
	select = "프리셋 선택",
	no_presets = "프리셋 없음",
	button_tip = "이 캐릭터 유형의 기술 트리 프리셋입니다.\n"
		.. "모든 캠페인에서 함께 사용됩니다.\n"
		.. "기술 좌클릭: 미리 배정\n"
		.. "레벨 숫자 좌클릭: 포인트 하나 제거",
	badge_tip = "미리 배정됨: %s 레벨에 습득",
	badge_tip_click = "마지막으로 미리 배정한 포인트를 제거하려면 여기를 클릭하세요",
	tip_new = "새 프리셋으로 저장",
	tip_overwrite = "선택한 프리셋 덮어쓰기",
	tip_rename = "선택한 프리셋 이름 바꾸기",
	tip_delete = "선택한 프리셋 삭제",
	tip_clear = "미리 배정 지우기",
	spend = "지금 포인트 %d개 배정",
	tip_spend = "지금 남은 기술 포인트를 미리 배정한 기술에 배정",
	ask_overwrite = "'%s' 프리셋을 덮어쓰시겠습니까?",
	ask_delete = "'%s' 프리셋을 삭제하시겠습니까?",
	ask_clear = "미리 배정한 포인트를 모두 지우시겠습니까?",
	ask_spend = "지금 포인트 %d개를 배정하시겠습니까?",
	heading_save = "새 프리셋으로 저장",
	heading_rename = "프리셋 이름 바꾸기",
	tip_plan = "계획 모드: 빈 기술 트리에서 1레벨부터\n기술 트리를 계획합니다. 이 모드에서는\n아무것도 습득하지 않습니다. 모드를 나가면\n계획이 미리 배정이 됩니다.",
	tip_plan_on = "계획 모드 나가기: 계획이 미리 배정이\n됩니다(이미 습득한 기술은 건너뜁니다).\n빈 계획은 아무것도 바꾸지 않습니다.",
	tip_spend_plan = "포인트를 배정하려면 계획 모드를 나가세요",
	tip_clear_plan = "계획 지우기 (처음부터 시작)",
	ask_clear_plan = "계획 전체를 지우고 처음부터 시작하시겠습니까?",
	default_name = "프리셋",
}

-- Simplified Chinese
S.cn = {
	select = "选择预设",
	no_presets = "无预设",
	button_tip = "此角色类型的技能树预设，所有战役通用。\n"
		.. "左键点击技能即可预分配，\n"
		.. "左键点击等级数字可移除一个技能点。",
	badge_tip = "已预分配：将在等级 %s 习得",
	badge_tip_click = "点击此处移除最后一个预分配的点数",
	tip_new = "另存为新预设",
	tip_overwrite = "覆盖所选预设",
	tip_rename = "重命名所选预设",
	tip_delete = "删除所选预设",
	tip_clear = "清除预分配",
	spend = "立即分配 %d 点",
	tip_spend = "立即将剩余技能点分配给预分配的技能",
	ask_overwrite = "覆盖预设“%s”？",
	ask_delete = "删除预设“%s”？",
	ask_clear = "清除所有预分配？",
	ask_spend = "立即分配 %d 点？",
	heading_save = "另存为新预设",
	heading_rename = "重命名预设",
	tip_plan = "规划模式：在空白技能树上从等级 1 开始规划，\n此模式下不会习得任何技能。\n退出后，规划将成为预分配。",
	tip_plan_on = "退出规划模式：规划将成为预分配\n（已习得的技能会被跳过）。\n空白规划不会改变任何内容。",
	tip_spend_plan = "退出规划模式后才能分配技能点",
	tip_clear_plan = "清除规划（从头开始）",
	ask_clear_plan = "清除整个规划并从头开始？",
	default_name = "预设",
}

-- Traditional Chinese
S.zh = {
	select = "選擇預設集",
	no_presets = "無預設集",
	button_tip = "此角色類型的技能樹預設集，所有戰役共用。\n"
		.. "左鍵點擊技能即可預分配，\n"
		.. "左鍵點擊等級數字可移除一個技能點。",
	badge_tip = "已預分配：將於等級 %s 習得",
	badge_tip_click = "點擊此處移除最後一個預分配的點數",
	tip_new = "另存為新預設集",
	tip_overwrite = "覆寫所選預設集",
	tip_rename = "重新命名所選預設集",
	tip_delete = "刪除所選預設集",
	tip_clear = "清除預分配",
	spend = "立即分配 %d 點",
	tip_spend = "立即將剩餘技能點分配給預分配的技能",
	ask_overwrite = "覆寫預設集「%s」？",
	ask_delete = "刪除預設集「%s」？",
	ask_clear = "清除所有預分配？",
	ask_spend = "立即分配 %d 點？",
	heading_save = "另存為新預設集",
	heading_rename = "重新命名預設集",
	tip_plan = "規劃模式：在空白技能樹上從等級 1 開始規劃，\n此模式下不會習得任何技能。\n離開後，規劃將成為預分配。",
	tip_plan_on = "離開規劃模式：規劃將成為預分配\n（已習得的技能會被略過）。\n空白規劃不會改變任何內容。",
	tip_spend_plan = "離開規劃模式後才能分配技能點",
	tip_clear_plan = "清除規劃（從頭開始）",
	ask_clear_plan = "清除整個規劃並從頭開始？",
	default_name = "預設集",
}

TEXT.languages = { "en", "fr", "ge", "it", "sp", "pl", "ru", "cz", "tr", "br", "kr", "cn", "zh" }

-- What the game may report -> the keys above. The game's own language files are named local_<key>.pack
-- (cn = Simplified, zh = Traditional Chinese); the other spellings are there in case LocLanguage
-- reports ISO codes, Steam's language names or the language's own name.
local ALIASES = {
	en = "en", english = "en", en_gb = "en", en_us = "en",
	fr = "fr", french = "fr", fr_fr = "fr", ["français"] = "fr", francais = "fr",
	ge = "ge", de = "ge", german = "ge", de_de = "ge", deutsch = "ge",
	it = "it", italian = "it", it_it = "it", italiano = "it",
	sp = "sp", es = "sp", spanish = "sp", es_es = "sp", ["español"] = "sp", espanol = "sp", latam = "sp", es_419 = "sp",
	pl = "pl", polish = "pl", pl_pl = "pl", polski = "pl",
	ru = "ru", russian = "ru", ru_ru = "ru", ["русский"] = "ru",
	cz = "cz", cs = "cz", czech = "cz", cs_cz = "cz", ["čeština"] = "cz", cestina = "cz",
	tr = "tr", turkish = "tr", tr_tr = "tr", ["türkçe"] = "tr", turkce = "tr",
	br = "br", pt = "br", pt_br = "br", brazilian = "br", portuguese = "br", ["português"] = "br",
	kr = "kr", ko = "kr", korean = "kr", koreana = "kr", ko_kr = "kr", ["한국어"] = "kr",
	cn = "cn", zh_cn = "cn", zh_hans = "cn", schinese = "cn", chs = "cn", ["简体中文"] = "cn",
	zh = "zh", zh_tw = "zh", zh_hant = "zh", tchinese = "zh", cht = "zh", ["繁體中文"] = "zh",
}

function TEXT.normalize(code)
	if type(code) ~= "string" or code == "" then return nil end
	if ALIASES[code] then return ALIASES[code] end
	local c = string.lower(code)
	c = string.gsub(c, "^%s+", "")
	c = string.gsub(c, "%s+$", "")
	c = string.gsub(c, "[%s%-]", "_")
	return ALIASES[c]
end

TEXT.lang = nil      -- the language in use, once known
TEXT.raw = nil       -- what the game reported
TEXT.tries = 0

-- Read the game's language (needs one of the player's characters for the context read). Unknown or
-- unreadable -> English; an unreadable language is retried a couple of times (one read each).
function TEXT.detect(cqi)
	if TEXT.lang or not cqi then return TEXT.lang end
	local ok, v = pcall(common.get_context_value, "CcoCampaignCharacter", cqi, "LocLanguage")
	if ok and v ~= nil and tostring(v) ~= "" then
		TEXT.raw = tostring(v)
		TEXT.lang = TEXT.normalize(TEXT.raw)
		if not TEXT.lang then
			TEXT.lang = "en"
			SPA.error("unknown game language \"" .. TEXT.raw .. "\": the mod's texts stay in English")
		end
		return TEXT.lang
	end
	TEXT.tries = TEXT.tries + 1
	if TEXT.tries >= 3 then
		TEXT.lang = "en"
		SPA.error("could not read the game language (LocLanguage gave " .. tostring(v) .. "): the mod's texts stay in English")
	end
	return TEXT.lang
end

function TEXT.get(key, ...)
	local lang = TEXT.lang or "en"
	local t = (S[lang] and S[lang][key]) or S.en[key] or key
	local n = select("#", ...)
	if type(t) == "table" then
		local first = ...
		t = (first == 1 and t.one) or t.other or t.one
	end
	if n > 0 then
		local ok, s = pcall(string.format, t, ...)
		if ok then return s end
	end
	return t
end
