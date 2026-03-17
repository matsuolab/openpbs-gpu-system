import pbs
import os
import json

NVIDIA_SMI = "/usr/bin/nvidia-smi"
ALLOC_FILE = "/var/spool/pbs/mom_priv/gpu_allocations.json"

def get_mig_uuids():
    try:
        fd = os.popen(NVIDIA_SMI + " -L 2>/dev/null")
        output = fd.read()
        fd.close()
        uuids = []
        for line in output.splitlines():
            if "MIG" in line and "UUID:" in line:
                uuid = line.split("UUID:")[1].strip().rstrip(")")
                uuids.append(uuid)
        return uuids
    except Exception as ex:
        pbs.logmsg(pbs.LOG_WARNING, "gpu_assign: get_mig_uuids failed: %s" % str(ex))
        return []

def get_gpu_indices():
    try:
        fd = os.popen(NVIDIA_SMI + " --query-gpu=index --format=csv,noheader 2>/dev/null")
        output = fd.read()
        fd.close()
        return [line.strip() for line in output.splitlines() if line.strip()]
    except Exception as ex:
        pbs.logmsg(pbs.LOG_WARNING, "gpu_assign: get_gpu_indices failed: %s" % str(ex))
        return []

def load_allocations():
    try:
        f = open(ALLOC_FILE, "r")
        data = json.load(f)
        f.close()
        return data
    except Exception:
        return {}

def save_allocations(allocs):
    try:
        f = open(ALLOC_FILE, "w")
        json.dump(allocs, f)
        f.close()
    except Exception as ex:
        pbs.logmsg(pbs.LOG_WARNING, "gpu_assign: save_allocations failed: %s" % str(ex))

e = pbs.event()

if e.type == pbs.EXECJOB_LAUNCH:
    j = e.job
    try:
        ngpus = int(j.Resource_List["ngpus"])
    except Exception:
        ngpus = 0

    pbs.logmsg(pbs.LOG_DEBUG, "gpu_assign: job=%s ngpus=%d" % (str(j.id), ngpus))

    if ngpus <= 0:
        e.accept()
    else:
        allocs = load_allocations()
        used = set()
        for devs in allocs.values():
            used.update(devs)

        mig_uuids = get_mig_uuids()
        pbs.logmsg(pbs.LOG_DEBUG, "gpu_assign: found %d MIG uuids, %d used" % (len(mig_uuids), len(used)))

        if mig_uuids:
            available = [u for u in mig_uuids if u not in used]
        else:
            available = [g for g in get_gpu_indices() if g not in used]

        pbs.logmsg(pbs.LOG_DEBUG, "gpu_assign: available=%d needed=%d" % (len(available), ngpus))

        if len(available) < ngpus:
            e.reject("Not enough GPUs: need %d, have %d free" % (ngpus, len(available)))
        else:
            assigned = available[:ngpus]
            allocs[str(j.id)] = assigned
            save_allocations(allocs)

            e.env["CUDA_VISIBLE_DEVICES"] = ",".join(assigned)
            e.env["NVIDIA_VISIBLE_DEVICES"] = ",".join(assigned)
            pbs.logmsg(pbs.LOG_DEBUG, "gpu_assign: assigned %s to %s" % (",".join(assigned), str(j.id)))
            e.accept()

elif e.type in (pbs.EXECJOB_EPILOGUE, pbs.EXECJOB_END):
    try:
        j = e.job
        allocs = load_allocations()
        allocs.pop(str(j.id), None)
        save_allocations(allocs)
    except Exception:
        pass
    e.accept()
