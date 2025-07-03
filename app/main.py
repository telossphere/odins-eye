#!/usr/bin/env python3
"""
Odin's AI - Main Application
FastAPI-based AI service with web interface
"""

import logging
import os
import subprocess
from datetime import datetime
from typing import Any, Dict, List

import psutil
import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Create FastAPI app
app = FastAPI(title="Odin's AI", description="Advanced AI/ML Platform", version="1.0.0")

# Mount static files
app.mount("/static", StaticFiles(directory="app/static"), name="static")

# Templates
templates = Jinja2Templates(directory="app/templates")


# System information
def get_system_info() -> dict[str, Any]:
    """Get system information"""
    try:
        # CPU info
        cpu_percent = psutil.cpu_percent(interval=1)
        cpu_count = psutil.cpu_count()

        # Memory info
        memory = psutil.virtual_memory()

        # Disk info
        disk = psutil.disk_usage("/")

        # GPU info (if available)
        gpu_info = "Not available"
        try:
            result = subprocess.run(
                [
                    "nvidia-smi",
                    "--query-gpu=name,memory.total,memory.used",
                    "--format=csv,noheader,nounits",
                ],
                capture_output=True,
                text=True,
                timeout=5,
            )
            if result.returncode == 0:
                gpu_info = result.stdout.strip()
        except (
            subprocess.TimeoutExpired,
            FileNotFoundError,
            subprocess.CalledProcessError,
        ):
            pass

        return {
            "cpu_percent": cpu_percent,
            "cpu_count": cpu_count,
            "memory_total": memory.total,
            "memory_used": memory.used,
            "memory_percent": memory.percent,
            "disk_total": disk.total,
            "disk_used": disk.used,
            "disk_percent": (disk.used / disk.total) * 100,
            "gpu_info": gpu_info,
            "timestamp": datetime.now().isoformat(),
        }
    except Exception as e:
        logger.error(f"Error getting system info: {e}")
        return {"error": str(e)}


@app.get("/", response_class=HTMLResponse)  # type: ignore[misc]
async def root(request: Request) -> Any:
    """Main dashboard page"""
    system_info = get_system_info()
    return templates.TemplateResponse(
        "dashboard.html", {"request": request, "system_info": system_info}
    )


@app.get("/gpu", response_class=HTMLResponse)  # type: ignore[misc]
async def gpu_monitor(request: Request) -> Any:
    """GPU monitoring page"""
    return templates.TemplateResponse("gpu-monitor.html", {"request": request})


@app.get("/api/status")  # type: ignore[misc]
async def status() -> dict[str, Any]:
    """API endpoint for system status"""
    return get_system_info()


@app.get("/api/health")  # type: ignore[misc]
async def health() -> dict[str, Any]:
    """Health check endpoint"""
    return {"status": "healthy", "timestamp": datetime.now().isoformat()}


@app.get("/api/services")  # type: ignore[misc]
async def services() -> dict[str, Any]:
    """Get running services status"""
    try:
        # Check if Docker is running and get container info
        docker_status = "unknown"
        containers: List[Dict[str, str]] = []
        error_details: List[str] = []

        try:
            # Check if Docker socket exists
            if not os.path.exists("/var/run/docker.sock"):
                docker_status = "socket not found"
                error_details.append("Docker socket /var/run/docker.sock not found")
                return {
                    "docker": docker_status,
                    "containers": containers,
                    "error_details": error_details,
                    "timestamp": datetime.now().isoformat(),
                }

            # Check if docker command is available
            result = subprocess.run(["which", "docker"], capture_output=True, text=True)
            if result.returncode != 0:
                docker_status = "docker command not found"
                error_details.append("Docker command not found in PATH")
                return {
                    "docker": docker_status,
                    "containers": containers,
                    "error_details": error_details,
                    "timestamp": datetime.now().isoformat(),
                }

            # Check if Docker is available
            result = subprocess.run(
                ["docker", "ps", "--format", "{{.Names}},{{.Status}},{{.Ports}}"],
                capture_output=True,
                text=True,
                timeout=5,
            )

            if result.returncode == 0:
                docker_status = "running"
                # Parse container information
                for line in result.stdout.strip().split("\n"):
                    if line.strip():
                        parts = line.split(",", 2)
                        if len(parts) >= 3:
                            containers.append(
                                {
                                    "name": parts[0],
                                    "status": parts[1],
                                    "ports": parts[2] if len(parts) > 2 else "",
                                }
                            )
            else:
                docker_status = "not running"
                error_details.append(f"Docker ps failed: {result.stderr.strip()}")
        except FileNotFoundError:
            docker_status = "not available"
            error_details.append("Docker command not found")
        except subprocess.TimeoutExpired:
            docker_status = "timeout"
            error_details.append("Docker command timed out")
        except Exception as e:
            docker_status = f"error: {str(e)}"
            error_details.append(f"Exception: {str(e)}")

        return {
            "docker": docker_status,
            "containers": containers,
            "error_details": error_details,
            "timestamp": datetime.now().isoformat(),
        }
    except Exception as e:
        logger.error(f"Error getting services status: {e}")
        return {"error": str(e)}


@app.get("/api/gpu")  # type: ignore[misc]
async def gpu_info() -> dict[str, Any]:
    """Get GPU information"""
    try:
        # First check if nvidia-smi is available
        result = subprocess.run(
            ["which", "nvidia-smi"], capture_output=True, text=True, timeout=2
        )
        if result.returncode != 0:
            return {
                "gpus": [],
                "message": "nvidia-smi not available in container",
                "timestamp": datetime.now().isoformat(),
            }

        result = subprocess.run(
            [
                "nvidia-smi",
                "--query-gpu=name,memory.total,memory.used,temperature.gpu,"
                "utilization.gpu",
                "--format=csv,noheader,nounits",
            ],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode == 0:
            gpu_data = result.stdout.strip().split("\n")
            gpus = []
            for line in gpu_data:
                if line.strip():
                    parts = line.split(", ")
                    if len(parts) >= 5:
                        gpus.append(
                            {
                                "name": parts[0],
                                "memory_total": parts[1],
                                "memory_used": parts[2],
                                "temperature": parts[3],
                                "utilization": parts[4],
                            }
                        )
            return {
                "gpus": gpus,
                "timestamp": datetime.now().isoformat(),
            }
        else:
            return {
                "gpus": [],
                "message": "nvidia-smi command failed",
                "timestamp": datetime.now().isoformat(),
            }
    except Exception as e:
        logger.error(f"Error getting GPU info: {e}")
        return {
            "gpus": [],
            "error": str(e),
            "timestamp": datetime.now().isoformat(),
        }


@app.get("/api/gpu/detailed")  # type: ignore[misc]
async def gpu_detailed() -> dict[str, Any]:
    """Get detailed GPU information with processes"""
    try:
        # Get detailed GPU info
        result = subprocess.run(
            [
                "nvidia-smi",
                "--query-gpu=index,name,memory.total,memory.used,memory.free,"
                "temperature.gpu,utilization.gpu,power.draw,power.limit,"
                "clocks.current.graphics,clocks.current.memory",
                "--format=csv,noheader,nounits",
            ],
            capture_output=True,
            text=True,
            timeout=5,
        )

        if result.returncode == 0:
            gpu_data = result.stdout.strip().split("\n")
            gpus = []

            for line in gpu_data:
                if line.strip():
                    parts = line.split(", ")
                    if len(parts) >= 11:
                        gpu = {
                            "index": parts[0],
                            "name": parts[1],
                            "memory_total": int(parts[2]),
                            "memory_used": int(parts[3]),
                            "memory_free": int(parts[4]),
                            "memory_percent": round(
                                (int(parts[3]) / int(parts[2])) * 100, 1
                            ),
                            "temperature": int(parts[5]),
                            "utilization": int(parts[6]),
                            "power_draw": float(parts[7]) if parts[7] != "N/A" else 0,
                            "power_limit": float(parts[8]) if parts[8] != "N/A" else 0,
                            "clock_graphics": int(parts[9]) if parts[9] != "N/A" else 0,
                            "clock_memory": int(parts[10]) if parts[10] != "N/A" else 0,
                        }
                        gpus.append(gpu)

            # Get GPU processes
            processes = []
            try:
                proc_result = subprocess.run(
                    [
                        "nvidia-smi",
                        "--query-compute-apps=gpu_uuid,pid,process_name,used_memory",
                        "--format=csv,noheader,nounits",
                    ],
                    capture_output=True,
                    text=True,
                    timeout=5,
                )

                if proc_result.returncode == 0:
                    for line in proc_result.stdout.strip().split("\n"):
                        if line.strip():
                            parts = line.split(", ")
                            if len(parts) >= 4:
                                processes.append(
                                    {
                                        "gpu_uuid": parts[0],
                                        "pid": parts[1],
                                        "process_name": parts[2],
                                        "memory_used": (
                                            int(parts[3]) if parts[3] != "N/A" else 0
                                        ),
                                    }
                                )
            except (
                subprocess.TimeoutExpired,
                FileNotFoundError,
                subprocess.CalledProcessError,
            ):
                pass

            return {
                "gpus": gpus,
                "processes": processes,
                "timestamp": datetime.now().isoformat(),
            }
        else:
            return {"error": "nvidia-smi not available"}
    except Exception as e:
        logger.error(f"Error getting detailed GPU info: {e}")
        return {"error": str(e)}


@app.get("/api/gpu/realtime")  # type: ignore[misc]
async def gpu_realtime() -> dict[str, Any]:
    """Get real-time GPU monitoring data for charts"""
    try:
        # Get real-time GPU stats
        result = subprocess.run(
            [
                "nvidia-smi",
                "--query-gpu=index,utilization.gpu,memory.used,memory.total,"
                "temperature.gpu,power.draw",
                "--format=csv,noheader,nounits",
            ],
            capture_output=True,
            text=True,
            timeout=5,
        )

        if result.returncode == 0:
            gpu_data = result.stdout.strip().split("\n")
            realtime_data = []

            for line in gpu_data:
                if line.strip():
                    parts = line.split(", ")
                    if len(parts) >= 6:
                        gpu = {
                            "index": int(parts[0]),
                            "utilization": int(parts[1]),
                            "memory_used": int(parts[2]),
                            "memory_total": int(parts[3]),
                            "memory_percent": round(
                                (int(parts[2]) / int(parts[3])) * 100, 1
                            ),
                            "temperature": int(parts[4]),
                            "power_draw": float(parts[5]) if parts[5] != "N/A" else 0,
                            "timestamp": datetime.now().timestamp(),
                        }
                        realtime_data.append(gpu)

            return {
                "gpus": realtime_data,
                "timestamp": datetime.now().isoformat(),
            }
        else:
            return {"error": "nvidia-smi not available"}
    except Exception as e:
        logger.error(f"Error getting real-time GPU info: {e}")
        return {"error": str(e)}


@app.get("/api/gpu/processes")  # type: ignore[misc]
async def gpu_processes() -> dict[str, Any]:
    """Get GPU processes with detailed information"""
    try:
        # First check if nvidia-smi is available
        result = subprocess.run(
            ["which", "nvidia-smi"], capture_output=True, text=True, timeout=2
        )
        if result.returncode != 0:
            return {
                "processes": [],
                "message": "nvidia-smi not available in container",
                "timestamp": datetime.now().isoformat(),
            }

        result = subprocess.run(
            [
                "nvidia-smi",
                "--query-compute-apps=gpu_uuid,pid,process_name,used_memory,"
                "process_type",
                "--format=csv,noheader,nounits",
            ],
            capture_output=True,
            text=True,
            timeout=5,
        )

        if result.returncode == 0:
            processes = []
            for line in result.stdout.strip().split("\n"):
                if line.strip():
                    parts = line.split(", ")
                    if len(parts) >= 5:
                        # Try to get process details
                        process_info = {
                            "gpu_uuid": parts[0],
                            "pid": parts[1],
                            "process_name": parts[2],
                            "memory_used": int(parts[3]) if parts[3] != "N/A" else 0,
                            "process_type": parts[4] if len(parts) > 4 else "Unknown",
                        }

                        # Try to get additional process info
                        try:
                            if parts[1] != "N/A":
                                ps_result = subprocess.run(
                                    [
                                        "ps",
                                        "-p",
                                        parts[1],
                                        "-o",
                                        "user,pcpu,pmem,etime,command",
                                        "--no-headers",
                                    ],
                                    capture_output=True,
                                    text=True,
                                    timeout=2,
                                )

                                if (
                                    ps_result.returncode == 0
                                    and ps_result.stdout.strip()
                                ):
                                    ps_parts = ps_result.stdout.strip().split()
                                    if len(ps_parts) >= 4:
                                        process_info.update(
                                            {
                                                "user": ps_parts[0],
                                                "cpu_percent": (
                                                    float(ps_parts[1])
                                                    if ps_parts[1] != "-"
                                                    else 0
                                                ),
                                                "memory_percent": (
                                                    float(ps_parts[2])
                                                    if ps_parts[2] != "-"
                                                    else 0
                                                ),
                                                "runtime": ps_parts[3],
                                                "command": (
                                                    " ".join(ps_parts[4:])
                                                    if len(ps_parts) > 4
                                                    else ""
                                                ),
                                            }
                                        )
                        except (
                            subprocess.TimeoutExpired,
                            FileNotFoundError,
                            subprocess.CalledProcessError,
                        ):
                            pass

                        processes.append(process_info)

            return {
                "processes": processes,
                "timestamp": datetime.now().isoformat(),
            }
        else:
            return {
                "processes": [],
                "message": "No GPU processes found or nvidia-smi error",
                "timestamp": datetime.now().isoformat(),
            }
    except Exception as e:
        logger.error(f"Error getting GPU processes: {e}")
        return {
            "processes": [],
            "error": str(e),
            "timestamp": datetime.now().isoformat(),
        }


@app.get("/api/debug/docker")  # type: ignore[misc]
async def debug_docker() -> dict[str, Any]:
    """Debug Docker access issues"""
    debug_info: Dict[str, Any] = {
        "docker_socket_exists": False,
        "docker_socket_permissions": "",
        "docker_command_available": False,
        "docker_group_exists": False,
        "user_groups": [],
        "error_details": [],
    }

    try:
        # Check if Docker socket exists
        import os

        debug_info["docker_socket_exists"] = os.path.exists("/var/run/docker.sock")

        if debug_info["docker_socket_exists"]:
            # Check socket permissions
            stat_info = os.stat("/var/run/docker.sock")
            debug_info["docker_socket_permissions"] = oct(stat_info.st_mode)[-3:]

        # Check if docker command is available
        result = subprocess.run(["which", "docker"], capture_output=True, text=True)
        debug_info["docker_command_available"] = result.returncode == 0

        # Check if docker group exists
        result = subprocess.run(
            ["getent", "group", "docker"], capture_output=True, text=True
        )
        debug_info["docker_group_exists"] = result.returncode == 0

        # Get user groups
        result = subprocess.run(["groups"], capture_output=True, text=True)
        if result.returncode == 0:
            debug_info["user_groups"] = result.stdout.strip().split()

        # Try to run docker ps
        result = subprocess.run(
            ["docker", "ps"], capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            debug_info["docker_ps_success"] = True
            debug_info["docker_ps_output"] = result.stdout.strip()
        else:
            debug_info["docker_ps_success"] = False
            debug_info["docker_ps_error"] = result.stderr.strip()

    except Exception as e:
        debug_info["error_details"].append(str(e))

    return debug_info


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
