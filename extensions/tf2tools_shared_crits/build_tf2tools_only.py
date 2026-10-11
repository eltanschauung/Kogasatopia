#!/usr/bin/env python3
"""Build only TF2Tools and required dependencies in a configured AMBuild tree."""
from pathlib import Path
from types import SimpleNamespace
import os
import sys
from ambuild2 import damage
from ambuild2.builder import Builder
from ambuild2.context import Context
from ambuild2.task import TaskMaster
from ambuild2 import util

build = str(Path(sys.argv[1]).resolve())
options = SimpleNamespace(no_color=True, jobs=1, refactor=False)
with util.FolderChanger(build), Context(build, options, []) as context:
    assert context.reconfigure(), 'Configure failed'
    graph = damage.ComputeDamageGraph(context.db)
    graph.filter_commands()
    roots = [node for node in graph.node_list
             if any(Path(out.path).name == 'game.tf2.ext.2.tf2.so'
                    for out in context.db.query_outgoing(node.entry))]
    if not roots:
        print('TF2Tools target is already current.')
        sys.exit(0)
    selected = set()
    def visit(node):
        if node in selected:
            return
        selected.add(node)
        for parent in node.incoming:
            visit(parent)
    for root in roots:
        visit(root)
    for node in selected:
        node.incoming.intersection_update(selected)
        node.outgoing.intersection_update(selected)
    graph.node_list = [node for node in graph.node_list if node in selected]
    print('Selected TF2Tools/dependency commands:', len(graph.node_list), flush=True)
    available = next(int(line.split()[1]) for line in Path('/proc/meminfo').read_text().splitlines()
                     if line.startswith('MemAvailable:'))
    assert available >= 512 * 1024, 'Insufficient memory headroom'
    status, message = Builder(context, graph).update()
    if status not in (TaskMaster.BUILD_SUCCEEDED, TaskMaster.BUILD_NO_CHANGES):
        raise RuntimeError(message or 'TF2Tools build failed')
