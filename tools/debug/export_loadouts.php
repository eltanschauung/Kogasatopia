#!/usr/bin/env php
<?php
// Read-only match/cookie extraction. No identities, config, or raw cookie values
// are printed. Generated profile fixtures belong outside Git, mode 0600.
declare(strict_types=1);
function tokens(string $text): array {
    preg_match_all('~"((?:\\\\.|[^"\\\\])*)"|([{}])|//[^\r\n]*|/\*.*?\*/~s', $text, $m, PREG_SET_ORDER);
    $out = [];
    foreach ($m as $v) {
        if ($v[0][0] === '"') $out[] = stripcslashes($v[1]);
        elseif ($v[0] === '{' || $v[0] === '}') $out[] = $v[0];
    }
    return $out;
}
function tree(array $tokens, int &$at): array {
    $out = [];
    while ($at < count($tokens)) {
        $key = $tokens[$at++];
        if ($key === '}') break;
        if ($at >= count($tokens)) throw new RuntimeException('Invalid KeyValues');
        $value = $tokens[$at++];
        $out[$key] = $value === '{' ? tree($tokens, $at) : $value;
    }
    return $out;
}
function quoteKV(string $text): string {
    return '"'.str_replace(['\\', '"', "\n", "\r"], ['\\\\', '\\"', '', ''], $text).'"';
}
try {
    if ($argc !== 4) throw new RuntimeException('Usage: export_loadouts.php databases.cfg clientprefs.sq3 PRIVATE_OUTPUT');
    umask(0077);
    if (file_exists($argv[3]) || is_link($argv[3])) throw new RuntimeException('Output must be new');
    $at = 0; $cfg = tree(tokens(file_get_contents($argv[1])), $at);
    $db = $cfg['Databases']['default'] ?? null;
    if (!is_array($db)) throw new RuntimeException('Default database entry unavailable');
    $dsn = 'mysql:host='.$db['host'].';port='.(($db['port'] ?? '') ?: '3306').';dbname='.$db['database'].';charset=utf8mb4';
    $sql = new PDO($dsn, $db['user'], $db['pass'], [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
    $sql->exec('SET SESSION TRANSACTION READ ONLY');
    $sql->beginTransaction();
    $logs = $sql->query("SELECT log_id, map, ended_at FROM whaletracker_logs WHERE finalized=1 AND ended_at>0 AND map NOT LIKE 'mge_%' ORDER BY ended_at DESC, log_id DESC LIMIT 10")->fetchAll(PDO::FETCH_ASSOC);
    if (count($logs) !== 10) throw new RuntimeException('Ten completed main-server matches required');
    $classes = [1=>'scout',2=>'sniper',3=>'soldier',4=>'demoman',5=>'medic',6=>'heavy',7=>'pyro',8=>'spy',9=>'engineer'];
    $columns = implode(',', array_map(fn($c)=>"SUM(shots_$c) AS shots_$c", $classes));
    $query = $sql->prepare('SELECT steamid, SUM(playtime) AS duration, '.$columns.' FROM whaletracker_log_players WHERE log_id IN ('.implode(',',array_fill(0,10,'?')).') GROUP BY steamid ORDER BY duration DESC, steamid LIMIT 128');
    $query->execute(array_column($logs,'log_id'));
    $players = $query->fetchAll(PDO::FETCH_ASSOC);
    $cookies = new PDO('sqlite:file:'.$argv[2].'?mode=ro');
    $cookies->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $cookies->exec('PRAGMA query_only=ON');
    $get = $cookies->prepare('SELECT c.name, v.value FROM sm_cookie_cache v JOIN sm_cookies c ON c.id=v.cookie_id WHERE v.player IN (?,?,?,?) AND (c.name LIKE \'cwx_loadout_%\' OR c.name LIKE \'custom_hats_state%\') ORDER BY c.name');
    $profiles=[]; $sourcePlayers=0; $nonempty=0; $hatCount=0;
    foreach ($players as $player) {
        $id = (int)$player['steamid'] - 76561197960265728;
        if ($id < 0 || $id > 4294967295) continue;
        $get->execute([$player['steamid'],'STEAM_0:'.($id%2).':'.intdiv($id,2),'STEAM_1:'.($id%2).':'.intdiv($id,2),'[U:1:'.$id.']']);
        $rows=$get->fetchAll(PDO::FETCH_ASSOC); $slots=[]; $hats=[];
        foreach ($rows as $row) {
            if (preg_match('/^cwx_loadout_([1-9])_([0-9]+)$/',$row['name'],$m) && (int)$m[2]<19 && preg_match('/^[A-Za-z0-9_\-]{1,63}$/',$row['value'])) {
                $slots[(int)$m[1]][(int)$m[2]]=$row['value'];
            } elseif (str_starts_with($row['name'],'custom_hats_state')) {
                foreach (explode(',',$row['value']) as $entry) {
                    if (preg_match('/^([A-Za-z0-9_\-]{1,63}):([0-9]{1,3})$/',trim($entry),$m)) $hats[$m[1]]=(int)$m[2];
                }
            }
        }
        if (!$slots) continue;
        $sourcePlayers++; $best=0; $bestShots=-1;
        foreach ($classes as $number=>$class) if (isset($slots[$number]) && (int)$player['shots_'.$class]>$bestShots) { $best=$number; $bestShots=(int)$player['shots_'.$class]; }
        $profiles[]=['class'=>$best,'slots'=>$slots,'hats'=>$hats];
        if (count($profiles)===16) break;
    }
    $sql->rollBack();
    if (!$profiles) throw new RuntimeException('No compatible saved custom loadouts found');
    $output="\"StressProfiles\"\n{\n";
    for ($index=0;$index<16;$index++) {
        $p=$profiles[$index%count($profiles)];
        $output.='  '.quoteKV((string)$index)."\n  {\n    \"class\" ".quoteKV((string)$p['class'])."\n    \"weapons\"\n    {\n";
        foreach ($p['slots'] as $class=>$slots) foreach ($slots as $slot=>$uid) { $output.='      '.quoteKV($class.'_'.$slot).' '.quoteKV($uid)."\n"; $nonempty++; }
        $output.="    }\n    \"hats\"\n    {\n";
        foreach ($p['hats'] as $hat=>$paint) { $output.='      '.quoteKV($hat).' '.quoteKV((string)$paint)."\n"; $hatCount++; }
        $output.="    }\n  }\n";
    }
    $output.="}\n";
    $handle=fopen($argv[3],'x'); fwrite($handle,$output); fclose($handle); chmod($argv[3],0600);
    echo json_encode(['matches'=>count($logs),'distinct_candidates'=>count($players),'source_profiles'=>count($profiles),'test_profiles'=>16,'weapon_selections'=>$nonempty,'hat_selections'=>$hatCount,'maps'=>array_column($logs,'map')],JSON_PRETTY_PRINT)."\n";
} catch (Throwable $error) {
    // Never expose PDO errors: they can contain server addresses or credentials.
    fwrite(STDERR,"Private extraction failed (".get_class($error)."); inspect configuration/schema privately.\n");
    exit(1);
}
